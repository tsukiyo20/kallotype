//! The densitometer: what an instrument reads off the developed strip.
//!
//! A characteristic curve is a property of the emulsion: how much dye formed at
//! a log exposure. A strip is not the curve — it is a developed object, and the
//! base it was coated on is still in the light path. A densitometer shines light
//! through the strip and reports how much it lost, so it reads the dye *and* the
//! base, the fog and the orange mask together. That is the number a darkroom
//! writes on the envelope, and the number a chart drawn beside a print is
//! supposed to be.
//!
//! [`FilmStock::base_density`] already carries that zero in status density, for
//! the non-spectral print: base, fog and the mask. [`Densitometer::read`] adds
//! it to a patch's dye. Status densities are per-record numbers, so they add;
//! the mask's exposure dependence is a property of the spectral print (see
//! [`PrintContext`](crate::PrintContext)), not of the three status records, and
//! this instrument does not invent it.
//!
//! ```text
//! dye + base ──► status density ──► the chart
//! ```
//!
//! A reversal is the exception that proves the rule: its curve already runs in
//! the slide's own density, from the unexposed maximum down to the clear film,
//! and its base is zero — reading it through a base would count the same light
//! twice. The stock's data says so, and [`Densitometer::for_stock`] follows it
//! rather than special-casing the process.

use crate::emulsion::FilmStock;

/// A transmission densitometer, held against one stock.
///
/// The instrument has one number per record: what it reads where no dye formed.
/// Everything else is the light a patch lost on top of that.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Densitometer {
    /// The unexposed, processed film in status density, per record.
    base: [f64; 3],
}

impl Densitometer {
    /// An instrument whose zero is `base_density`, in status density.
    #[must_use]
    pub fn new(base_density: [f64; 3]) -> Self {
        Self { base: base_density }
    }

    /// The instrument for a stock, with its own unexposed film as the zero.
    #[must_use]
    pub fn for_stock(stock: &FilmStock) -> Self {
        Self::new(stock.base_density)
    }

    /// What the instrument reads where no dye formed: base, fog and mask.
    #[must_use]
    pub fn base_density(&self) -> [f64; 3] {
        self.base
    }

    /// Read a patch: the dye the development formed, plus the base under it.
    #[must_use]
    pub fn read(&self, dye_density: [f64; 3]) -> [f64; 3] {
        std::array::from_fn(|channel| dye_density[channel] + self.base[channel])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::emulsion::film_stock;

    #[test]
    fn an_unexposed_strip_reads_its_base() {
        let stock = film_stock("vision3_500t").expect("the measured stock exists");
        let instrument = Densitometer::for_stock(stock);
        assert_eq!(instrument.read([0.0; 3]), stock.base_density);
        // A colour negative's base is not grey: the mask absorbs blue.
        assert!(instrument.base_density()[2] > instrument.base_density()[0]);
    }

    #[test]
    fn a_reading_is_gross_not_above_base() {
        let instrument = Densitometer::new([0.20, 0.50, 0.80]);
        let reading = instrument.read([1.0, 1.0, 1.0]);
        assert_eq!(reading, [1.20, 1.50, 1.80]);
        for (gross, dye) in reading.iter().zip([1.0; 3]) {
            assert!(*gross > dye);
        }
    }

    #[test]
    fn a_clear_base_leaves_the_dye_alone() {
        let instrument = Densitometer::new([0.0; 3]);
        assert_eq!(instrument.read([0.3, 1.2, 2.7]), [0.3, 1.2, 2.7]);
    }

    #[test]
    fn a_reversal_is_read_without_a_base() {
        // The curve already runs in the slide's density, so a base here would
        // count the same light twice. The stock's own data carries the zero.
        let stock = film_stock("provia_100f").expect("the reversal exists");
        assert_eq!(stock.base_density, [0.0; 3]);
        assert_eq!(
            Densitometer::for_stock(stock).read([1.0, 1.0, 1.0]),
            [1.0; 3]
        );
    }
}
