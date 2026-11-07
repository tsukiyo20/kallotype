//! Halation: the light that comes back.
//!
//! Light entering the emulsion does not all stop there. Some of it reaches the
//! base, scatters, and reflects off the back surface — the film base, a glass
//! carrier, the pressure plate — and returns into the emulsion to expose it a
//! second time. Because the returning light is out of focus and has already
//! crossed the layers once, the result is a **red-orange glow around bright
//! highlights**, not a white one.
//!
//! Two components are modelled, both as energy-preserving kernels:
//!
//! - **scatter**, micrometres wide, roughly colour-neutral: a short-range
//!   diffusion inside the emulsion;
//! - **reflection**, tens of micrometres wide, strongly red: the light that went
//!   all the way down and came back through the yellow filter layer and the
//!   silver halide again.
//!
//! Each Gaussian kernel sums to one, so the blur moves light rather than
//! creating it. The only place energy is added is `strength`: the fraction of
//! the blurred exposure that returns to each layer. That energy is real — it is
//! light that would otherwise have left the film through the back.
//!
//! Halation is applied to the **exposure**, before development, because that is
//! where it happens: it is light exposing the emulsion, not a property of the
//! developed image. That is why it runs before grain rather than after it.
//!
//! ## What is not modelled
//!
//! The strengths and the two radii are placeholders. The red bias has the right
//! *shape* — a double pass through the yellow filter layer cannot leave blue
//! intact — but the numbers describe a modern colour negative in general, not
//! this film. Measuring them means photographing a controlled highlight and
//! reading the halo's falloff, which is a camera experiment, not a data sheet.

/// One halation component: how far the light spreads and how much returns.
#[derive(Debug, Clone, Copy)]
pub struct Halo {
    /// Standard deviation of the spread on the film, in micrometres.
    pub sigma_um: f64,
    /// Fraction of the blurred exposure added back, per layer (R, G, B).
    pub strength: [f64; 3],
}

/// Both halation components for one image, with its scale on the film.
#[derive(Debug, Clone, Copy)]
pub struct Halation {
    /// Size of one pixel on the film, in micrometres across.
    pub pixel_um: f64,
    /// Diffusion inside the emulsion: short, and almost colour-neutral.
    pub scatter: Halo,
    /// Reflection off the base: long, and red by the time it returns.
    pub reflection: Halo,
}

impl Halation {
    /// Placeholder values for a modern colour negative.
    ///
    /// `pixel_um` is the film-plane size of one pixel, so the kernels are
    /// expressed in micrometres and do not change when the scan resolution does.
    #[must_use]
    pub fn typical(pixel_um: f64) -> Self {
        Self {
            pixel_um,
            scatter: Halo {
                sigma_um: 6.0,
                strength: [0.020, 0.018, 0.015],
            },
            reflection: Halo {
                sigma_um: 30.0,
                strength: [0.090, 0.030, 0.012],
            },
        }
    }

    /// Whether either component would change anything.
    #[must_use]
    pub fn is_noop(&self) -> bool {
        let inert =
            |halo: &Halo| halo.sigma_um <= 0.0 || halo.strength.iter().all(|&value| value <= 0.0);
        inert(&self.scatter) && inert(&self.reflection)
    }

    /// Apply halation to a buffer of log10 exposures, in place.
    ///
    /// `width * height` is read from the buffer; a buffer that is shorter than
    /// the declared rectangle is processed only as far as it goes.
    pub fn apply(&self, log_e: &mut [[f64; 3]], width: usize, height: usize) {
        if self.is_noop() || width == 0 || height == 0 {
            return;
        }
        let pixels = (width * height).min(log_e.len());
        let height = pixels / width;
        if height == 0 {
            return;
        }

        // The light that reaches the base is what the scene threw at the film,
        // not the density it produced, so the halo source is the incident
        // exposure averaged over the layers.
        let mut source = Vec::with_capacity(pixels);
        for pixel in &log_e[..pixels] {
            let sum: f64 = pixel.iter().map(|&value| 10.0_f64.powf(value)).sum();
            source.push(sum / 3.0);
        }

        let scatter = self.halo_plane(&source, width, height, &self.scatter);
        let reflection = self.halo_plane(&source, width, height, &self.reflection);

        for (index, pixel) in log_e.iter_mut().enumerate().take(pixels) {
            for (channel, value) in pixel.iter_mut().enumerate() {
                let exposure = 10.0_f64.powf(*value).max(1e-10);
                let added = self.scatter.strength[channel] * scatter[index]
                    + self.reflection.strength[channel] * reflection[index];
                // The halo is light, so it adds to the exposure and then goes
                // back through the logarithm: a black area next to a highlight
                // really does get exposed.
                *value = (exposure + added).log10();
            }
        }
    }

    /// One component's blurred source plane, or zeros when inert.
    fn halo_plane(&self, source: &[f64], width: usize, height: usize, halo: &Halo) -> Vec<f64> {
        if halo.sigma_um <= 0.0 || halo.strength.iter().all(|&value| value <= 0.0) {
            return vec![0.0; source.len()];
        }
        let sigma_px = halo.sigma_um / self.pixel_um.max(1e-9);
        crate::psf::gaussian_blur(source, width, height, sigma_px)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::psf::gaussian_blur as blur;
    use crate::psf::gaussian_kernel;

    const W: usize = 64;
    const H: usize = 64;

    /// A black frame with one bright pixel in the middle.
    fn highlight(log_e: f64) -> Vec<[f64; 3]> {
        let mut buffer = vec![[-6.0; 3]; W * H];
        buffer[(H / 2) * W + W / 2] = [log_e; 3];
        buffer
    }

    /// The kernel moves light; it does not create it. A flat plane has to come
    /// out flat and equal, or the blur is not normalised.
    #[test]
    fn the_blur_preserves_a_flat_plane() {
        let plane = vec![0.25; W * H];
        let blurred = blur(&plane, W, H, 3.0);
        for value in blurred {
            assert!((value - 0.25).abs() < 1e-12, "{value}");
        }
    }

    /// Halation *does* add light — that is the whole point, the reflection
    /// returns exposure that would otherwise have left the film. On a uniform
    /// field the gain is exactly the sum of the strengths, everywhere.
    #[test]
    fn a_flat_frame_gains_exactly_the_strengths() {
        let mut buffer = vec![[0.2, 0.2, 0.2]; W * H];
        let halation = Halation::typical(6.0);
        halation.apply(&mut buffer, W, H);
        let gain = 1.0 + halation.scatter.strength[0] + halation.reflection.strength[0];
        let expected = 0.2 + gain.log10();
        for pixel in &buffer {
            assert!(
                (pixel[0] - expected).abs() < 1e-9,
                "{:?} vs {expected}",
                pixel[0]
            );
        }
    }

    /// The halo has to be red: the same returned light, weighted by how much of
    /// each layer survives the double pass.
    #[test]
    fn the_glow_is_red() {
        let mut buffer = highlight(3.0);
        Halation::typical(6.0).apply(&mut buffer, W, H);
        let near = (H / 2) * W + W / 2 + 3;
        let pixel = buffer[near];
        assert!(pixel[0] > pixel[1], "red {pixel:?}");
        assert!(pixel[1] > pixel[2], "green over blue {pixel:?}");
    }

    #[test]
    fn the_halo_falls_off_with_distance() {
        let mut buffer = highlight(3.0);
        Halation::typical(6.0).apply(&mut buffer, W, H);
        let at = |offset: usize| buffer[(H / 2) * W + W / 2 + offset][0];
        assert!(at(1) > at(5), "near {} vs far {}", at(1), at(5));
        assert!(at(5) > at(20), "near {} vs far {}", at(5), at(20));
    }

    /// The kernels are in micrometres, so the scan resolution must not change how
    /// much light comes back — only how many pixels it is spread over.
    #[test]
    fn the_returned_energy_does_not_depend_on_the_scan() {
        let energy = |pixel_um: f64| {
            let mut buffer = highlight(3.0);
            let before: f64 = buffer.iter().map(|p| 10.0_f64.powf(p[0])).sum();
            Halation::typical(pixel_um).apply(&mut buffer, W, H);
            let after: f64 = buffer.iter().map(|p| 10.0_f64.powf(p[0])).sum();
            after - before
        };
        let fine = energy(3.0);
        let coarse = energy(12.0);
        let relative = (fine - coarse).abs() / fine;
        assert!(relative < 0.01, "fine {fine} vs coarse {coarse}");
    }

    /// And the halo really is larger in pixels when the pixels are smaller.
    #[test]
    fn the_halo_widens_when_the_pixels_shrink() {
        let reach = |pixel_um: f64| {
            let mut buffer = highlight(3.0);
            Halation::typical(pixel_um).apply(&mut buffer, W, H);
            // A thousand times the unexposed level: inside the halo core, and
            // well outside it once the glow has fallen away.
            let row = &buffer[(H / 2) * W..(H / 2 + 1) * W];
            row.iter().filter(|pixel| pixel[0] > -2.0).count()
        };
        let fine = reach(3.0);
        let coarse = reach(12.0);
        assert!(fine > coarse, "fine {fine} px vs coarse {coarse} px");
    }

    #[test]
    fn a_zero_strength_is_a_no_op() {
        let mut halation = Halation::typical(6.0);
        halation.reflection.strength = [0.0; 3];
        halation.scatter.strength = [0.0; 3];
        assert!(halation.is_noop());
        let mut buffer = highlight(4.0);
        let before = buffer.clone();
        halation.apply(&mut buffer, W, H);
        assert_eq!(buffer, before);
    }

    /// The kernel sums to one, so a uniform field stays put even at the edges,
    /// where clamping would otherwise lose or invent light.
    #[test]
    fn the_kernel_is_normalised() {
        let kernel = gaussian_kernel(2.5);
        let sum: f64 = kernel.iter().sum();
        assert!((sum - 1.0).abs() < 1e-12, "sum {sum}");
    }
}
