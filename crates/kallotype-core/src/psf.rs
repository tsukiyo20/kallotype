//! Point-spread helpers shared by the physics that moves light between pixels.
//!
//! Halation and the inhibitor released by DIR couplers are different physics with
//! the same shape: a quantity produced at one pixel arrives, reduced, at its
//! neighbours. Both are modelled as a Gaussian whose width is given in
//! micrometres of film, so a change of scan resolution changes the pixel count
//! and not the physics.

/// A separable Gaussian blur with clamped edges and a unit-sum kernel.
///
/// The kernel sums to one, so the pass moves a quantity rather than creating it;
/// clamping at the edges keeps that true in the border pixels too.
#[must_use]
pub fn gaussian_blur(plane: &[f64], width: usize, height: usize, sigma_px: f64) -> Vec<f64> {
    if sigma_px <= 0.0 || width == 0 || height == 0 || plane.len() < width * height {
        return vec![0.0; plane.len()];
    }
    convolve(plane, width, height, &gaussian_kernel(sigma_px))
}

/// One separable pass with an arbitrary kernel, clamped at the edges.
///
/// Separated from [`gaussian_blur`] because the kernel is not always the L1
/// Gaussian: the grain and the scan's texture filter with an L2-normalised one,
/// which keeps variance instead of light, and rebuilding the convolution for
/// that would be a second definition of the edge rule.
#[must_use]
pub fn convolve(plane: &[f64], width: usize, height: usize, kernel: &[f64]) -> Vec<f64> {
    if kernel.is_empty() || width == 0 || height == 0 || plane.len() < width * height {
        return vec![0.0; plane.len()];
    }
    let radius = kernel.len() / 2;
    let last_x = width.saturating_sub(1) as isize;
    let last_y = height.saturating_sub(1) as isize;

    let mut horizontal = vec![0.0; plane.len()];
    for y in 0..height {
        let row = &plane[y * width..(y + 1) * width];
        for (x, out) in horizontal[y * width..(y + 1) * width]
            .iter_mut()
            .enumerate()
        {
            let mut sum = 0.0;
            for (offset, &weight) in kernel.iter().enumerate() {
                let source_x = (x as isize + offset as isize - radius as isize).clamp(0, last_x);
                sum += weight * row[source_x as usize];
            }
            *out = sum;
        }
    }

    let mut out = vec![0.0; plane.len()];
    for y in 0..height {
        for x in 0..width {
            let mut sum = 0.0;
            for (offset, &weight) in kernel.iter().enumerate() {
                let source_y = (y as isize + offset as isize - radius as isize).clamp(0, last_y);
                sum += weight * horizontal[source_y as usize * width + x];
            }
            out[y * width + x] = sum;
        }
    }
    out
}

/// A normalised Gaussian, three standard deviations out.
///
/// Public because a backend that convolves has to convolve with the *same*
/// numbers. Rebuilding the kernel on the other side would be a second definition
/// of the blur, and the two would agree until someone changed a radius.
#[must_use]
pub fn gaussian_kernel(sigma_px: f64) -> Vec<f64> {
    let radius = (3.0 * sigma_px).ceil().max(1.0) as usize;
    let mut kernel: Vec<f64> = (0..=2 * radius)
        .map(|index| {
            let distance = index as f64 - radius as f64;
            (-0.5 * (distance / sigma_px).powi(2)).exp()
        })
        .collect();
    let sum: f64 = kernel.iter().sum();
    if sum > 0.0 {
        for weight in &mut kernel {
            *weight /= sum;
        }
    }
    kernel
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_kernel_is_normalised() {
        let kernel = gaussian_kernel(2.5);
        let sum: f64 = kernel.iter().sum();
        assert!((sum - 1.0).abs() < 1e-12, "sum {sum}");
    }

    #[test]
    fn a_flat_plane_survives_the_blur() {
        let plane = vec![0.25; 32 * 16];
        for value in gaussian_blur(&plane, 32, 16, 3.0) {
            assert!((value - 0.25).abs() < 1e-12, "{value}");
        }
    }

    #[test]
    fn a_single_point_spreads_and_keeps_its_total() {
        let mut plane = vec![0.0; 64 * 64];
        plane[32 * 64 + 32] = 1.0;
        let blurred = gaussian_blur(&plane, 64, 64, 2.0);
        let total: f64 = blurred.iter().sum();
        assert!((total - 1.0).abs() < 1e-9, "total {total}");
        assert!(blurred[32 * 64 + 34] > 0.0, "the point did not spread");
    }
}
