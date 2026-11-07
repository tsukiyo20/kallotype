//! Couplers: the chemistry that makes a colour negative more than three layers.
//!
//! Two effects are modelled here, and both are about what a layer does to its
//! neighbours rather than to itself.
//!
//! ## DIR couplers
//!
//! A development-inhibitor-releasing coupler does what its name says: as a layer
//! develops, it releases an inhibitor, which diffuses a short way and suppresses
//! further development — in its own layer and in the ones next to it. Three
//! things follow, and all three are visible in a real negative:
//!
//! - **interimage effects**: a strong exposure in one layer pulls the others
//!   back, which is a colour correction built out of chemistry rather than out of
//!   a matrix;
//! - **highlight contrast loss**: the inhibition grows with development, so the
//!   top of the curve is compressed in a way the H&D curve alone does not show;
//! - **edge effects**: because the inhibitor diffuses, the suppression is
//!   stronger next to a developed area than inside it, which leaves a light line
//!   against a dark one — the Mackie line.
//!
//! The model is a **matrix with a spatial kernel**: each layer releases an amount
//! that saturates with its density, the release diffuses by a Gaussian in
//! micrometres of film, and layer `i` loses `Σ_j M[i][j] · release_j` of its own
//! density.
//!
//! ## Masking couplers
//!
//! Not here: they act on the dye's *absorption spectrum*, so they belong to
//! [`crate::print`], and they are only visible when the spectral print is on.
//! This module is the density-space half of the phase.
//!
//! ## What is not modelled
//!
//! The matrix is a placeholder. It has the right structure — positive, saturating,
//! and stronger across layers than within one — but its numbers describe colour
//! negative film in general. [`fit_inhibition`] exists so that they can be
//! replaced by a fit to measured patches instead of by another guess.

/// The inhibition each layer releases, given its density.
///
/// Saturating, because the coupler is consumed: a layer that has developed
/// everything it can does not release more inhibitor.
#[must_use]
pub fn release(density: &[f64; 3], half_saturation: f64) -> [f64; 3] {
    let half = half_saturation.max(1e-9);
    std::array::from_fn(|layer| {
        let value = density[layer].max(0.0);
        value / (value + half)
    })
}

/// Apply an inhibition matrix to one pixel.
///
/// `release` is the already-diffused release at this pixel, so the same function
/// serves a uniform patch (where diffusion changes nothing) and a frame.
#[must_use]
pub fn inhibit(density: &[f64; 3], release: &[f64; 3], matrix: &[[f64; 3]; 3]) -> [f64; 3] {
    std::array::from_fn(|layer| {
        let suppressed: f64 = (0..3)
            .map(|other| matrix[layer][other] * release[other])
            .sum();
        (density[layer] * (1.0 - suppressed).max(0.0)).max(0.0)
    })
}

/// DIR couplers for one image.
#[derive(Debug, Clone, Copy)]
pub struct Couplers {
    /// `inhibition[i][j]`: how much layer `j` suppresses layer `i`. The diagonal
    /// is a layer suppressing itself, which is the highlight compression; the
    /// off-diagonal is the interimage effect.
    pub inhibition: [[f64; 3]; 3],
    /// Density at which a layer releases half of the inhibitor it can.
    pub half_saturation: f64,
    /// How far the inhibitor diffuses on the film, in micrometres.
    pub sigma_um: f64,
    /// Size of one pixel on the film, in micrometres across.
    pub pixel_um: f64,
}

impl Couplers {
    /// Placeholder values for a modern colour negative.
    #[must_use]
    pub fn typical(pixel_um: f64) -> Self {
        Self {
            // Rows are the layer being suppressed, columns the one doing it.
            // The off-diagonal terms are the point — interimage correction — and
            // they are larger than the self term. Row sums land near 0.07, so the
            // strongest inhibition takes about 7 % off a fully developed density.
            // An earlier placeholder used 0.42 and turned the test chart grey,
            // which is a useful reminder that these are numbers, not structure.
            inhibition: [
                [0.020, 0.030, 0.020],
                [0.030, 0.020, 0.030],
                [0.020, 0.030, 0.020],
            ],
            half_saturation: 0.5,
            sigma_um: 20.0,
            pixel_um,
        }
    }

    /// Whether this would change anything.
    #[must_use]
    pub fn is_noop(&self) -> bool {
        self.inhibition
            .iter()
            .all(|row| row.iter().all(|&value| value <= 0.0))
    }

    /// Apply the couplers to a buffer of densities, in place.
    pub fn apply(&self, density: &mut [[f64; 3]], width: usize, height: usize) {
        if self.is_noop() || width == 0 || height == 0 {
            return;
        }
        let pixels = (width * height).min(density.len());
        let height = pixels / width;
        if height == 0 {
            return;
        }

        // Each layer releases from its own density, saturating.
        let mut planes: [Vec<f64>; 3] = [vec![0.0; pixels], vec![0.0; pixels], vec![0.0; pixels]];
        for (index, pixel) in density[..pixels].iter().enumerate() {
            let released = release(pixel, self.half_saturation);
            for layer in 0..3 {
                planes[layer][index] = released[layer];
            }
        }

        // The inhibitor diffuses before it acts, which is what turns a local
        // suppression into an edge effect.
        let sigma_px = self.sigma_um / self.pixel_um.max(1e-9);
        let diffused: [Vec<f64>; 3] = std::array::from_fn(|layer| {
            crate::psf::gaussian_blur(&planes[layer], width, height, sigma_px)
        });

        for (index, pixel) in density.iter_mut().enumerate().take(pixels) {
            let released = [diffused[0][index], diffused[1][index], diffused[2][index]];
            *pixel = inhibit(pixel, &released, &self.inhibition);
        }
    }
}

/// Fit an inhibition matrix to measured densities.
///
/// Both slices are the same set of **uniform patches**, not a frame: on a uniform
/// patch the inhibitor's diffusion changes nothing, so the spatial term drops out
/// and what is left is linear in the matrix. For each output layer the fit is an
/// ordinary least-squares solve of
///
/// ```text
/// measured_i = D_i · (1 − Σ_j M[i][j] · u_j)
/// ```
///
/// where `D` is the density the model predicts without couplers and `u` is the
/// release that follows from it. The result is clipped to `[0, 1]`: a negative
/// inhibition would mean a coupler that accelerates development, which is not
/// what these are.
#[must_use]
pub fn fit_inhibition(
    uninhibited: &[[f64; 3]],
    measured: &[[f64; 3]],
    half_saturation: f64,
) -> [[f64; 3]; 3] {
    let mut matrix = [[0.0; 3]; 3];
    for layer in 0..3 {
        let mut normal = [[0.0; 3]; 3];
        let mut rhs = [0.0; 3];
        for (predicted, observed) in uninhibited.iter().zip(measured) {
            let density = predicted[layer].max(0.0);
            if density <= 1e-9 {
                continue;
            }
            let released = release(predicted, half_saturation);
            let target = density - observed[layer].max(0.0);
            for row in 0..3 {
                let x_row = density * released[row];
                rhs[row] += x_row * target;
                for column in 0..3 {
                    normal[row][column] += x_row * density * released[column];
                }
            }
        }
        // A tiny ridge keeps a patch set that never develops a layer from
        // producing a singular system.
        for (index, row) in normal.iter_mut().enumerate() {
            row[index] += 1e-9;
        }
        if let Some(solution) = crate::scan::solve3(normal, rhs) {
            for column in 0..3 {
                matrix[layer][column] = solution[column].clamp(0.0, 1.0);
            }
        }
    }
    matrix
}

#[cfg(test)]
mod tests {
    use super::*;

    fn patches() -> Vec<[f64; 3]> {
        let mut out = Vec::new();
        for r in [0.1, 0.4, 0.9, 1.6, 2.2] {
            out.push([r, 0.3 * r, 0.2 * r]);
            out.push([0.3 * r, r, 0.25 * r]);
            out.push([0.2 * r, 0.3 * r, r]);
        }
        out
    }

    #[test]
    fn release_saturates() {
        assert!(release(&[0.0; 3], 0.5)[0] < 1e-12);
        assert!((release(&[0.5; 3], 0.5)[0] - 0.5).abs() < 1e-12);
        assert!(release(&[50.0; 3], 0.5)[0] > 0.98);
    }

    /// The point of the fit: if the data came from a matrix, the fit has to find
    /// that matrix. This is what makes "fitted to scans" checkable without scans.
    #[test]
    fn the_fit_recovers_the_matrix_that_made_the_data() {
        let truth = [[0.10, 0.22, 0.10], [0.22, 0.10, 0.22], [0.10, 0.22, 0.10]];
        let half = 0.5;
        let uninhibited = patches();
        let measured: Vec<[f64; 3]> = uninhibited
            .iter()
            .map(|density| inhibit(density, &release(density, half), &truth))
            .collect();
        let fitted = fit_inhibition(&uninhibited, &measured, half);
        for layer in 0..3 {
            for other in 0..3 {
                assert!(
                    (fitted[layer][other] - truth[layer][other]).abs() < 1e-6,
                    "layer {layer} from {other}: {} vs {}",
                    fitted[layer][other],
                    truth[layer][other]
                );
            }
        }
    }

    #[test]
    fn a_strong_layer_pulls_the_others_back() {
        let couplers = Couplers::typical(6.0);
        let mut buffer = vec![[0.0; 3]; 16 * 16];
        buffer[8 * 16 + 8] = [1.5, 0.2, 0.2];
        let before = buffer.clone();
        couplers.apply(&mut buffer, 16, 16);
        let centre = buffer[8 * 16 + 8];
        assert!(
            centre[0] < before[8 * 16 + 8][0],
            "self-inhibition {centre:?}"
        );
        assert!(centre[1] < before[8 * 16 + 8][1], "interimage on green");
    }

    /// The inhibitor diffuses, so a pixel next to a dense one loses more than a
    /// pixel far away — which is the edge effect, and it is why this is a
    /// convolution and not a lookup.
    #[test]
    fn the_suppression_falls_off_with_distance() {
        let couplers = Couplers::typical(6.0);
        let mut buffer = vec![[1.0; 3]; 64 * 64];
        buffer[32 * 64 + 32] = [3.0; 3];
        let before = buffer.clone();
        couplers.apply(&mut buffer, 64, 64);
        let loss =
            |offset: usize| before[32 * 64 + 32 + offset][0] - buffer[32 * 64 + 32 + offset][0];
        assert!(loss(1) > loss(6), "near {} far {}", loss(1), loss(6));
        assert!(loss(6) > loss(20), "mid {} far {}", loss(6), loss(20));
    }

    #[test]
    fn a_zero_matrix_is_a_no_op() {
        let mut couplers = Couplers::typical(6.0);
        couplers.inhibition = [[0.0; 3]; 3];
        assert!(couplers.is_noop());
        let mut buffer = vec![[1.0, 0.5, 0.2]; 8 * 8];
        let before = buffer.clone();
        couplers.apply(&mut buffer, 8, 8);
        assert_eq!(buffer, before);
    }
}
