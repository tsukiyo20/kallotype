//! The spectral model, flattened into numbers another backend can replay.
//!
//! The scalar path was easy to hand over: six numbers per layer and the
//! enlarger's four, all of them the *answers* to the model. The spectral path
//! integrates over wavelength, so there is no answer to hand over — only the
//! tables the integration runs on. That is what lives here.
//!
//! Three things are deliberately **not** re-derived on the other side:
//!
//! - the **polynomial basis**, because it is the only thing between a camera's
//!   three numbers and a spectrum;
//! - the **three 3×3 systems** (the exposure reconstruction, the print's
//!   status-to-analytical unmixing and the scan's), because they are inverted
//!   here by the same Gaussian elimination the CPU solves with, so the shader
//!   does a matrix multiply and cannot drift in pivot order;
//! - the **grey-balance anchors**, which are themselves integrals and would
//!   otherwise have to be recomputed per render on the device.
//!
//! Everything else is a measured or fitted curve, copied verbatim.
//!
//! ## What is here, and what is not
//!
//! The exposure is only the *closed-form* one. A dictionary prior solves a
//! non-negative least squares per pixel, and a baked table samples a cube; both
//! are their own models, and neither is expressible as a constant matrix.
//! [`PreparedRender::spectral_model`](crate::PreparedRender::spectral_model)
//! therefore declines them rather than rendering something adjacent.

use kallotype_spectral::Spectrum;

use crate::scan::solve3;
use crate::spectral::GRID_LEN;

/// The exposure: camera triple to per-layer log exposure.
#[derive(Debug, Clone, PartialEq)]
pub struct ExposureModel {
    /// Row-major inverse of the system [`PolynomialUpsampler::system`] builds.
    /// Coefficients are `reconstruct · rgb`.
    ///
    /// The zero matrix and the CPU's own fallback agree: when the system is
    /// singular the upsampler returns zero coefficients, and a zero matrix is
    /// exactly that for every input.
    ///
    /// [`PolynomialUpsampler::system`]: kallotype_spectral::PolynomialUpsampler::system
    pub reconstruct: [[f64; 3]; 3],
    /// The three basis terms, one row each.
    pub basis: [[f64; GRID_LEN]; 3],
    /// The film's layer sensitivities, one row each.
    pub film: [[f64; GRID_LEN]; 3],
    /// The film's response to a reconstructed 18 % grey, per layer.
    pub reference: [f64; 3],
}

/// The enlarger and the paper: negative density to paper layer exposure.
#[derive(Debug, Clone, PartialEq)]
pub struct PrintModel {
    /// Row-major inverse of the status-to-analytical unmixing.
    pub analytical: [[f64; 3]; 3],
    /// Whether the CPU clamps the unmixed densities to zero.
    ///
    /// It does whenever the system solved, and does not when it fell back to
    /// the identity. Carrying the flag is cheaper than pretending a fallback
    /// cannot happen.
    pub clamped: bool,
    /// The negative's dye absorption, peak-normalised, one row per dye.
    pub dye: [[f64; GRID_LEN]; 3],
    /// The paper's layer sensitivities.
    pub paper: [[f64; GRID_LEN]; 3],
    /// The enlarger's light source.
    pub illuminant: [f64; GRID_LEN],
    /// The film's minimum density — base, fog and the orange mask. All zeros
    /// when the context has none, which is the same thing the CPU does when
    /// `base_density` is `None`.
    pub mask: [f64; GRID_LEN],
    /// Fraction of the mask each layer destroys at `masking_reference`.
    ///
    /// All zeros when masking is off: the surviving fraction is then one, so
    /// the mask is constant, which is what no masking means.
    pub masking: [f64; 3],
    /// Density at which a layer has destroyed all the mask it can.
    pub masking_reference: f64,
    /// The enlarger's filter pack, in colour-correction units.
    pub filters: [f64; 3],
    /// The three filter absorption bands.
    pub filter_bands: [[f64; GRID_LEN]; 3],
    /// The grey balance at the reference density, per layer.
    pub reference: [f64; 3],
}

/// The scan: print density to linear-light RGB.
#[derive(Debug, Clone, PartialEq)]
pub struct ScanModel {
    /// Row-major inverse of the status-to-analytical unmixing.
    pub analytical: [[f64; 3]; 3],
    /// Whether the CPU clamps the unmixed densities to zero.
    pub clamped: bool,
    /// The paper's image dyes.
    pub dye: [[f64; GRID_LEN]; 3],
    /// The viewing illuminant.
    pub illuminant: [f64; GRID_LEN],
    /// The colour matching functions, one row per axis.
    pub cmf: [[f64; GRID_LEN]; 3],
    /// Row-major XYZ to linear sRGB matrix.
    pub matrix: [[f64; 3]; 3],
    /// XYZ of paper white.
    pub white_xyz: [f64; 3],
    /// RGB of paper white.
    pub white_rgb: [f64; 3],
    /// RGB along the neutral axis, evenly spaced in density.
    pub neutral: [[f64; 3]; NEUTRAL_ENTRIES],
    /// Density covered by `neutral`.
    pub neutral_max_density: f64,
    /// Base density of the unexposed paper.
    pub base_density: f64,
}

/// Entries in [`ScanModel::neutral`]: `NEUTRAL_STEPS + 1`.
pub const NEUTRAL_ENTRIES: usize = crate::scan::NEUTRAL_ENTRIES;

/// Every constant a spectral render integrates with.
#[derive(Debug, Clone, PartialEq)]
pub struct SpectralModel {
    /// The curve, the paper and the enlarger, which are the scalar model's
    /// numbers and are applied identically here.
    pub scalar: crate::pipeline::ScalarModel,
    /// Wavelength step of every table below.
    ///
    /// One number for the whole model, not one per stage: all three integrate on
    /// the same grid, and a stage that carried its own copy could be zero while
    /// another was not — which multiplies that stage's integral by zero and
    /// looks like a dark frame.
    pub step_nm: f64,
    /// The exposure, when it is the closed-form reconstruction.
    pub exposure: Option<ExposureModel>,
    /// The print, when it goes through dye absorption.
    pub enlarger: Option<PrintModel>,
    /// The scan, when it goes through reflectance.
    pub scan: Option<ScanModel>,
}

impl SpectralModel {
    /// Whether any stage integrates over wavelength.
    ///
    /// A model where this is false is the scalar path, and
    /// [`PreparedRender::scalar_model`](crate::PreparedRender::scalar_model)
    /// describes it with four numbers per layer instead.
    #[must_use]
    pub fn is_spectral(&self) -> bool {
        self.exposure.is_some() || self.enlarger.is_some() || self.scan.is_some()
    }
}

/// The inverse of a 3×3 matrix, or `None` when it is singular.
///
/// Inverting once per render rather than solving per pixel: the three systems
/// are built from cameras, dyes and observers, none of which depend on the
/// pixel, so a shader that solved them would be doing the same work sixty
/// million times.
pub(crate) fn inverse3(matrix: [[f64; 3]; 3]) -> Option<[[f64; 3]; 3]> {
    let mut inverse = [[0.0_f64; 3]; 3];
    for column in 0..3 {
        let mut unit = [0.0_f64; 3];
        unit[column] = 1.0;
        let solved = solve3(matrix, unit)?;
        for (row, entries) in inverse.iter_mut().enumerate() {
            entries[column] = solved[row];
        }
    }
    Some(inverse)
}

/// A spectrum's samples as a fixed-size table, or `None` if it is not on the
/// model's grid.
pub(crate) fn table(spectrum: &Spectrum) -> Option<[f64; GRID_LEN]> {
    spectrum.values().try_into().ok()
}

/// Three spectra as three fixed-size tables.
pub(crate) fn tables(spectra: &[Spectrum; 3]) -> Option<[[f64; GRID_LEN]; 3]> {
    Some([
        table(&spectra[0])?,
        table(&spectra[1])?,
        table(&spectra[2])?,
    ])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_inverse_multiplies_back_to_the_identity() {
        let matrix = [[2.0, -1.0, 0.5], [0.0, 3.0, -2.0], [1.0, 1.0, 1.0]];
        let inverse = inverse3(matrix).expect("the test matrix is invertible");
        for (row, products) in matrix.iter().enumerate() {
            for (column, inverse_column) in [0, 1, 2].iter().enumerate() {
                let sum: f64 = products
                    .iter()
                    .zip(&inverse)
                    .map(|(left, right)| left * right[*inverse_column])
                    .sum();
                let expected = if row == column { 1.0 } else { 0.0 };
                assert!((sum - expected).abs() < 1e-12, "{row},{column}: {sum}");
            }
        }
    }

    #[test]
    fn a_singular_matrix_has_no_inverse() {
        let matrix = [[1.0, 2.0, 3.0], [2.0, 4.0, 6.0], [0.0, 1.0, 1.0]];
        assert!(inverse3(matrix).is_none());
    }

    /// A render with no spectral stage is the scalar path, and must say so:
    /// the two descriptions have to be mutually exclusive or a backend would
    /// have to choose between them.
    #[test]
    fn a_plain_render_has_a_scalar_model_and_no_spectral_one() {
        let prepared = crate::pipeline::RenderParams::default().prepare();
        assert!(prepared.scalar_model().is_some());
        assert!(prepared.spectral_model().is_none());
    }
}
