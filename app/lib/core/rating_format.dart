/// One-decimal player label; comparisons continue to use the stored number.
/// A rating below ten must not become a perfect score through display rounding.
String formatPlayerRating(double rating) =>
    (rating < 10 ? rating.clamp(0.0, 9.9) : rating).toStringAsFixed(1);
