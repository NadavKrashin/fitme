import Foundation

/// Finds an item's dominant colors from its photo pixels.
///
/// Clusters pixels with k-means in OKLab, where distance tracks perceived difference, so a navy shirt's shadows and
/// highlights merge into one "navy" instead of splitting into several blues.
public enum ColorExtractor {
    /// Clusters smaller than this share of the item are noise (seams, logos, shadows) and are dropped.
    private static let minimumShare = 0.08
    /// Clusters closer than this are the same color in practice and are merged.
    private static let mergeDistance = 0.06
    private static let iterations = 12

    /// - Parameters:
    ///   - pixels: The item's pixels only (background already removed).
    ///   - maxColors: Upper bound on colors returned.
    /// - Returns: Colors with their share of the item, largest first, shares summing to 1.
    public static func dominantColors(in pixels: [RGB], maxColors: Int = 3) -> [ItemColor] {
        guard !pixels.isEmpty, maxColors > 0 else { return [] }
        let points = pixels.map(OKLab.init)
        var centers = initialCenters(points, count: min(maxColors, points.count))
        var assignment = [Int](repeating: 0, count: points.count)

        for _ in 0 ..< iterations {
            for (i, point) in points.enumerated() {
                assignment[i] = nearest(point, in: centers)
            }
            centers = centers.indices.map { c in
                let members = points.indices.filter { assignment[$0] == c }.map { points[$0] }
                return members.isEmpty ? centers[c] : mean(members)
            }
        }

        var clusters = centers.indices.map { c in
            (center: centers[c], pixelCount: assignment.count(where: { $0 == c }))
        }
        clusters = merged(clusters)
            .filter { Double($0.pixelCount) / Double(points.count) >= minimumShare }
            .sorted { $0.pixelCount > $1.pixelCount }

        let total = Double(clusters.map(\.pixelCount).reduce(0, +))
        return clusters.map { cluster in
            ItemColor(hex: rgb(from: cluster.center).hex, proportion: Double(cluster.pixelCount) / total)
        }
    }

    /// Deterministic k-means++-style seeding: start from the average color, then repeatedly take the point farthest
    /// from every chosen center. Same input always gives the same output.
    private static func initialCenters(_ points: [OKLab], count: Int) -> [OKLab] {
        var centers = [mean(points)]
        while centers.count < count {
            let farthest = points.max { a, b in
                minDistance(a, centers) < minDistance(b, centers)
            }
            guard let farthest, minDistance(farthest, centers) > 0 else { break }
            centers.append(farthest)
        }
        return centers
    }

    private static func merged(_ clusters: [(center: OKLab, pixelCount: Int)]) -> [(center: OKLab, pixelCount: Int)] {
        var result: [(center: OKLab, pixelCount: Int)] = []
        for cluster in clusters.sorted(by: { $0.pixelCount > $1.pixelCount }) where cluster.pixelCount != 0 {
            if let index = result.firstIndex(where: { $0.center.distance(to: cluster.center) < mergeDistance }) {
                result[index].pixelCount += cluster.pixelCount
            } else {
                result.append(cluster)
            }
        }
        return result
    }

    private static func nearest(_ point: OKLab, in centers: [OKLab]) -> Int {
        var best = 0
        var bestDistance = Double.infinity
        for (i, center) in centers.enumerated() {
            let d = point.distance(to: center)
            if d < bestDistance {
                best = i
                bestDistance = d
            }
        }
        return best
    }

    private static func minDistance(_ point: OKLab, _ centers: [OKLab]) -> Double {
        centers.map { point.distance(to: $0) }.min() ?? .infinity
    }

    private static func mean(_ points: [OKLab]) -> OKLab {
        let n = Double(points.count)
        return OKLab(
            L: points.map(\.L).reduce(0, +) / n,
            a: points.map(\.a).reduce(0, +) / n,
            b: points.map(\.b).reduce(0, +) / n
        )
    }

    /// Inverse of `OKLab.init(_ rgb:)`, clamped to the sRGB gamut.
    static func rgb(from lab: OKLab) -> RGB {
        let l = pow(lab.L + 0.3963377774 * lab.a + 0.2158037573 * lab.b, 3)
        let m = pow(lab.L - 0.1055613458 * lab.a - 0.0638541728 * lab.b, 3)
        let s = pow(lab.L - 0.0894841775 * lab.a - 1.2914855480 * lab.b, 3)
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return RGB(r: gammaEncode(r), g: gammaEncode(g), b: gammaEncode(b))
    }

    private static func gammaEncode(_ c: Double) -> Double {
        let clamped = min(max(c, 0), 1)
        return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }
}
