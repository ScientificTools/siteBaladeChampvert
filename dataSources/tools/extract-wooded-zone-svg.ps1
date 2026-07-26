Add-Type -AssemblyName System.Drawing

$sourcePath = Join-Path $PSScriptRoot 'openStreetViewCalque.png'
$mapPath = Join-Path $PSScriptRoot 'openStreetViewcarte.png'
$svgPath = Join-Path $PSScriptRoot 'openStreetViewBois.svg'
$overlayPath = Join-Path $PSScriptRoot 'openStreetViewBois-overlay.png'
$comparisonPath = Join-Path $PSScriptRoot 'openStreetViewBois-comparaison.png'

$typeDefinition = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public struct GridPoint : IEquatable<GridPoint>
{
    public int X;
    public int Y;

    public GridPoint(int x, int y)
    {
        X = x;
        Y = y;
    }

    public bool Equals(GridPoint other)
    {
        return X == other.X && Y == other.Y;
    }

    public override bool Equals(object obj)
    {
        if (!(obj is GridPoint))
        {
            return false;
        }

        return Equals((GridPoint)obj);
    }

    public override int GetHashCode()
    {
        return (X * 397) ^ Y;
    }

    public override string ToString()
    {
        return X.ToString(CultureInfo.InvariantCulture) + "," + Y.ToString(CultureInfo.InvariantCulture);
    }
}

public sealed class Edge : IEquatable<Edge>
{
    public GridPoint Start;
    public GridPoint End;

    public Edge(GridPoint start, GridPoint end)
    {
        Start = start;
        End = end;
    }

    public bool Equals(Edge other)
    {
        if (ReferenceEquals(other, null)) return false;
        return Start.Equals(other.Start) && End.Equals(other.End);
    }

    public override bool Equals(object obj)
    {
        return Equals(obj as Edge);
    }

    public override int GetHashCode()
    {
        return (Start.GetHashCode() * 397) ^ End.GetHashCode();
    }
}

public static class WoodedZoneVectorizer
{
    public static bool[] BuildMask(Bitmap bitmap, out int width, out int height)
    {
        width = bitmap.Width;
        height = bitmap.Height;
        var mask = new bool[width * height];

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                var color = bitmap.GetPixel(x, y);
                bool isGreen = color.A > 0 && color.G >= 110 && color.G >= color.R + 10 && color.G >= color.B + 10;
                mask[(y * width) + x] = isGreen;
            }
        }

        return mask;
    }

    public static List<List<PointF>> ExtractLoops(bool[] mask, int width, int height, double simplifyTolerance, double minArea)
    {
        var edges = new HashSet<Edge>();

        Func<int, int, bool> isFilled = (x, y) =>
        {
            if (x < 0 || y < 0 || x >= width || y >= height) return false;
            return mask[(y * width) + x];
        };

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                if (!mask[(y * width) + x]) continue;

                if (!isFilled(x, y - 1))
                {
                    edges.Add(new Edge(new GridPoint(x, y), new GridPoint(x + 1, y)));
                }

                if (!isFilled(x + 1, y))
                {
                    edges.Add(new Edge(new GridPoint(x + 1, y), new GridPoint(x + 1, y + 1)));
                }

                if (!isFilled(x, y + 1))
                {
                    edges.Add(new Edge(new GridPoint(x + 1, y + 1), new GridPoint(x, y + 1)));
                }

                if (!isFilled(x - 1, y))
                {
                    edges.Add(new Edge(new GridPoint(x, y + 1), new GridPoint(x, y)));
                }
            }
        }

        var nextByStart = new Dictionary<GridPoint, List<GridPoint>>();
        foreach (var edge in edges)
        {
            List<GridPoint> list;
            if (!nextByStart.TryGetValue(edge.Start, out list))
            {
                list = new List<GridPoint>();
                nextByStart[edge.Start] = list;
            }
            list.Add(edge.End);
        }

        var visited = new HashSet<Edge>();
        var loops = new List<List<PointF>>();

        foreach (var edge in edges)
        {
            if (visited.Contains(edge)) continue;

            var loop = new List<GridPoint>();
            var currentStart = edge.Start;
            var currentEnd = edge.End;
            visited.Add(edge);
            loop.Add(currentStart);
            loop.Add(currentEnd);

            while (!currentEnd.Equals(loop[0]))
            {
                List<GridPoint> nextCandidates;
                if (!nextByStart.TryGetValue(currentEnd, out nextCandidates) || nextCandidates.Count == 0)
                {
                    throw new InvalidDataException("Contour ouvert détecté lors de la reconstruction du polygone.");
                }

                GridPoint nextPoint = default(GridPoint);
                bool found = false;
                foreach (var candidate in nextCandidates)
                {
                    var nextEdge = new Edge(currentEnd, candidate);
                    if (visited.Contains(nextEdge)) continue;
                    nextPoint = candidate;
                    visited.Add(nextEdge);
                    found = true;
                    break;
                }

                if (!found)
                {
                    break;
                }

                currentStart = currentEnd;
                currentEnd = nextPoint;
                loop.Add(currentEnd);
            }

            if (loop.Count < 4) continue;

            if (loop[loop.Count - 1].Equals(loop[0]))
            {
                loop.RemoveAt(loop.Count - 1);
            }

            var reduced = RemoveCollinear(loop);
            var simplified = SimplifyClosedLoop(reduced, simplifyTolerance);
            double area = Math.Abs(SignedArea(simplified));

            if (area >= minArea)
            {
                loops.Add(simplified.Select(p => new PointF(p.X, p.Y)).ToList());
            }
        }

        loops.Sort((a, b) => Math.Abs(SignedArea(b.Select(p => new GridPoint((int)p.X, (int)p.Y)).ToList())).CompareTo(Math.Abs(SignedArea(a.Select(p => new GridPoint((int)p.X, (int)p.Y)).ToList()))));
        return loops;
    }

    public static bool[] BuildHoleMask(bool[] filledMask, int width, int height)
    {
        var background = new bool[width * height];
        var queue = new Queue<GridPoint>();

        Action<int, int> enqueueBackground = delegate(int x, int y)
        {
            if (x < 0 || y < 0 || x >= width || y >= height) return;
            int index = (y * width) + x;
            if (filledMask[index] || background[index]) return;
            background[index] = true;
            queue.Enqueue(new GridPoint(x, y));
        };

        for (int x = 0; x < width; x++)
        {
            enqueueBackground(x, 0);
            enqueueBackground(x, height - 1);
        }

        for (int y = 0; y < height; y++)
        {
            enqueueBackground(0, y);
            enqueueBackground(width - 1, y);
        }

        int[] offsetX = new int[] { 1, -1, 0, 0 };
        int[] offsetY = new int[] { 0, 0, 1, -1 };

        while (queue.Count > 0)
        {
            var point = queue.Dequeue();
            for (int i = 0; i < 4; i++)
            {
                enqueueBackground(point.X + offsetX[i], point.Y + offsetY[i]);
            }
        }

        var holeMask = new bool[width * height];
        for (int i = 0; i < holeMask.Length; i++)
        {
            holeMask[i] = !filledMask[i] && !background[i];
        }

        return holeMask;
    }

    public static bool[] CloseMask(bool[] mask, int width, int height, int radius)
    {
        var dilated = Dilate(mask, width, height, radius);
        return Erode(dilated, width, height, radius);
    }

    private static bool[] Dilate(bool[] mask, int width, int height, int radius)
    {
        var result = new bool[mask.Length];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                bool filled = false;
                for (int dy = -radius; dy <= radius && !filled; dy++)
                {
                    int ny = y + dy;
                    if (ny < 0 || ny >= height) continue;
                    for (int dx = -radius; dx <= radius; dx++)
                    {
                        int nx = x + dx;
                        if (nx < 0 || nx >= width) continue;
                        if (mask[(ny * width) + nx])
                        {
                            filled = true;
                            break;
                        }
                    }
                }

                result[(y * width) + x] = filled;
            }
        }

        return result;
    }

    private static bool[] Erode(bool[] mask, int width, int height, int radius)
    {
        var result = new bool[mask.Length];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                bool filled = true;
                for (int dy = -radius; dy <= radius && filled; dy++)
                {
                    int ny = y + dy;
                    if (ny < 0 || ny >= height)
                    {
                        filled = false;
                        break;
                    }

                    for (int dx = -radius; dx <= radius; dx++)
                    {
                        int nx = x + dx;
                        if (nx < 0 || nx >= width || !mask[(ny * width) + nx])
                        {
                            filled = false;
                            break;
                        }
                    }
                }

                result[(y * width) + x] = filled;
            }
        }

        return result;
    }

    private static List<GridPoint> RemoveCollinear(List<GridPoint> points)
    {
        var result = new List<GridPoint>();
        for (int i = 0; i < points.Count; i++)
        {
            var prev = points[(i - 1 + points.Count) % points.Count];
            var current = points[i];
            var next = points[(i + 1) % points.Count];

            int dx1 = current.X - prev.X;
            int dy1 = current.Y - prev.Y;
            int dx2 = next.X - current.X;
            int dy2 = next.Y - current.Y;

            if ((dx1 == 0 && dx2 == 0) || (dy1 == 0 && dy2 == 0))
            {
                continue;
            }

            result.Add(current);
        }

        return result.Count >= 3 ? result : new List<GridPoint>(points);
    }

    private static List<GridPoint> SimplifyClosedLoop(List<GridPoint> loop, double tolerance)
    {
        if (loop.Count <= 3 || tolerance <= 0) return new List<GridPoint>(loop);

        int anchorIndex = 0;
        for (int i = 1; i < loop.Count; i++)
        {
            if (loop[i].X < loop[anchorIndex].X || (loop[i].X == loop[anchorIndex].X && loop[i].Y < loop[anchorIndex].Y))
            {
                anchorIndex = i;
            }
        }

        var reordered = new List<GridPoint>();
        for (int i = 0; i < loop.Count; i++)
        {
            reordered.Add(loop[(anchorIndex + i) % loop.Count]);
        }
        reordered.Add(reordered[0]);

        var simplified = SimplifyPolyline(reordered, tolerance);
        if (simplified.Count > 1 && simplified[simplified.Count - 1].Equals(simplified[0]))
        {
            simplified.RemoveAt(simplified.Count - 1);
        }

        return simplified.Count >= 3 ? simplified : new List<GridPoint>(loop);
    }

    private static List<GridPoint> SimplifyPolyline(List<GridPoint> points, double tolerance)
    {
        if (points.Count < 3) return new List<GridPoint>(points);

        var keep = new bool[points.Count];
        keep[0] = true;
        keep[points.Count - 1] = true;
        SimplifySection(points, 0, points.Count - 1, tolerance, keep);

        var result = new List<GridPoint>();
        for (int i = 0; i < points.Count; i++)
        {
            if (keep[i]) result.Add(points[i]);
        }

        return result;
    }

    private static void SimplifySection(List<GridPoint> points, int start, int end, double tolerance, bool[] keep)
    {
        if (end <= start + 1) return;

        double maxDistance = -1.0;
        int index = -1;
        for (int i = start + 1; i < end; i++)
        {
            double distance = PerpendicularDistance(points[i], points[start], points[end]);
            if (distance > maxDistance)
            {
                maxDistance = distance;
                index = i;
            }
        }

        if (maxDistance > tolerance && index != -1)
        {
            keep[index] = true;
            SimplifySection(points, start, index, tolerance, keep);
            SimplifySection(points, index, end, tolerance, keep);
        }
    }

    private static double PerpendicularDistance(GridPoint point, GridPoint lineStart, GridPoint lineEnd)
    {
        double dx = lineEnd.X - lineStart.X;
        double dy = lineEnd.Y - lineStart.Y;

        if (dx == 0 && dy == 0)
        {
            dx = point.X - lineStart.X;
            dy = point.Y - lineStart.Y;
            return Math.Sqrt((dx * dx) + (dy * dy));
        }

        double numerator = Math.Abs((dy * point.X) - (dx * point.Y) + (lineEnd.X * lineStart.Y) - (lineEnd.Y * lineStart.X));
        double denominator = Math.Sqrt((dx * dx) + (dy * dy));
        return numerator / denominator;
    }

    public static double SignedArea(List<GridPoint> points)
    {
        double area = 0.0;
        for (int i = 0; i < points.Count; i++)
        {
            var current = points[i];
            var next = points[(i + 1) % points.Count];
            area += ((double)current.X * next.Y) - ((double)next.X * current.Y);
        }

        return area / 2.0;
    }

    private static double SignedArea(List<PointF> points)
    {
        double area = 0.0;
        for (int i = 0; i < points.Count; i++)
        {
            var current = points[i];
            var next = points[(i + 1) % points.Count];
            area += (current.X * next.Y) - (next.X * current.Y);
        }

        return area / 2.0;
    }

    public static void SaveSvg(string path, int width, int height, List<List<PointF>> loops)
    {
        var sb = new StringBuilder();
        sb.AppendLine("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
        sb.AppendLine("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + width.ToString(CultureInfo.InvariantCulture) + "\" height=\"" + height.ToString(CultureInfo.InvariantCulture) + "\" viewBox=\"0 0 " + width.ToString(CultureInfo.InvariantCulture) + " " + height.ToString(CultureInfo.InvariantCulture) + "\">");
        sb.AppendLine("  <path fill=\"#9BCB65\" fill-opacity=\"0.72\" stroke=\"#79A84D\" stroke-width=\"2\" fill-rule=\"evenodd\" d=\"" + BuildPathData(loops) + "\" />");
        sb.AppendLine("</svg>");
        File.WriteAllText(path, sb.ToString(), new UTF8Encoding(false));
    }

    private static string BuildPathData(List<List<PointF>> loops)
    {
        var sb = new StringBuilder();
        foreach (var loop in loops)
        {
            if (loop.Count < 3) continue;

            sb.Append("M ");
            for (int i = 0; i < loop.Count; i++)
            {
                var point = loop[i];
                if (i > 0) sb.Append(" L ");
                sb.Append(point.X.ToString("0.###", CultureInfo.InvariantCulture));
                sb.Append(" ");
                sb.Append(point.Y.ToString("0.###", CultureInfo.InvariantCulture));
            }
            sb.Append(" Z ");
        }

        return sb.ToString().Trim();
    }

    public static void SaveOverlay(string mapPath, string outputPath, int width, int height, List<List<PointF>> loops)
    {
        using (var map = new Bitmap(mapPath))
        using (var canvas = new Bitmap(width, height, PixelFormat.Format32bppArgb))
        using (var graphics = Graphics.FromImage(canvas))
        using (var fillBrush = new SolidBrush(Color.FromArgb(115, 155, 203, 101)))
        using (var strokePen = new Pen(Color.FromArgb(210, 121, 168, 77), 3f))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.Clear(Color.White);
            graphics.DrawImage(map, 0, 0, width, height);

            using (var path = BuildGraphicsPath(loops))
            {
                graphics.FillPath(fillBrush, path);
                graphics.DrawPath(strokePen, path);
            }

            canvas.Save(outputPath, ImageFormat.Png);
        }
    }

    public static void SaveComparison(string mapPath, string calquePath, string outputPath, int width, int height, List<List<PointF>> loops)
    {
        using (var map = new Bitmap(mapPath))
        using (var calque = new Bitmap(calquePath))
        using (var vectorRender = new Bitmap(width, height, PixelFormat.Format32bppArgb))
        using (var vectorGraphics = Graphics.FromImage(vectorRender))
        using (var fillBrush = new SolidBrush(Color.FromArgb(200, 155, 203, 101)))
        using (var strokePen = new Pen(Color.FromArgb(220, 121, 168, 77), 3f))
        {
            vectorGraphics.SmoothingMode = SmoothingMode.AntiAlias;
            vectorGraphics.Clear(Color.White);
            using (var path = BuildGraphicsPath(loops))
            {
                vectorGraphics.FillPath(fillBrush, path);
                vectorGraphics.DrawPath(strokePen, path);
            }

            using (var comparison = new Bitmap(width * 3, height, PixelFormat.Format32bppArgb))
            using (var graphics = Graphics.FromImage(comparison))
            using (var titleFont = new Font("Arial", 20, FontStyle.Bold))
            using (var titleBrush = new SolidBrush(Color.FromArgb(220, 60, 60, 60)))
            {
                graphics.SmoothingMode = SmoothingMode.AntiAlias;
                graphics.Clear(Color.White);
                graphics.DrawImage(map, 0, 0, width, height);
                graphics.DrawImage(calque, width, 0, width, height);
                graphics.DrawImage(vectorRender, width * 2, 0, width, height);

                graphics.FillRectangle(new SolidBrush(Color.FromArgb(180, 255, 255, 255)), 0, 0, width, 42);
                graphics.FillRectangle(new SolidBrush(Color.FromArgb(180, 255, 255, 255)), width, 0, width, 42);
                graphics.FillRectangle(new SolidBrush(Color.FromArgb(180, 255, 255, 255)), width * 2, 0, width, 42);

                graphics.DrawString("Carte source", titleFont, titleBrush, new PointF(16, 8));
                graphics.DrawString("Calque bitmap", titleFont, titleBrush, new PointF(width + 16, 8));
                graphics.DrawString("Polygone vectoriel", titleFont, titleBrush, new PointF((width * 2) + 16, 8));

                comparison.Save(outputPath, ImageFormat.Png);
            }
        }
    }

    private static GraphicsPath BuildGraphicsPath(List<List<PointF>> loops)
    {
        var path = new GraphicsPath(FillMode.Alternate);
        foreach (var loop in loops)
        {
            if (loop.Count < 3) continue;
            path.AddPolygon(loop.ToArray());
        }

        return path;
    }
}
"@

Add-Type -TypeDefinition $typeDefinition -ReferencedAssemblies @(
    'System.Drawing.dll',
    'System.Core.dll'
) -Language CSharp

if (-not (Test-Path $sourcePath)) {
    throw "Fichier source introuvable: $sourcePath"
}

if (-not (Test-Path $mapPath)) {
    throw "Fichier carte introuvable: $mapPath"
}

$bitmap = [System.Drawing.Bitmap]::FromFile($sourcePath)
try {
    $width = 0
    $height = 0
    $mask = [WoodedZoneVectorizer]::BuildMask($bitmap, [ref]$width, [ref]$height)
    $closedMask = [WoodedZoneVectorizer]::CloseMask($mask, $width, $height, 1)
    $outerLoops = [WoodedZoneVectorizer]::ExtractLoops($closedMask, $width, $height, 2.2, 2000.0)
    $holeMask = [WoodedZoneVectorizer]::BuildHoleMask($closedMask, $width, $height)
    $holeLoops = [WoodedZoneVectorizer]::ExtractLoops($holeMask, $width, $height, 2.2, 2000.0)
    $loops = New-Object 'System.Collections.Generic.List[System.Collections.Generic.List[System.Drawing.PointF]]'
    foreach ($loop in $outerLoops) {
        $loops.Add($loop)
    }

    if ($outerLoops.Count -lt 1) {
        throw "Aucun contour externe n'a été détecté."
    }

    foreach ($loop in $holeLoops) {
        if ($loop.Count -gt 20) {
            $loops.Add($loop)
        }
    }

    [WoodedZoneVectorizer]::SaveSvg($svgPath, $width, $height, $loops)
    [WoodedZoneVectorizer]::SaveOverlay($mapPath, $overlayPath, $width, $height, $loops)
    [WoodedZoneVectorizer]::SaveComparison($mapPath, $sourcePath, $comparisonPath, $width, $height, $loops)

    $largestLoop = $loops | Sort-Object { $_.Count } -Descending | Select-Object -First 1
    [pscustomobject]@{
        Width = $width
        Height = $height
        OuterLoopCount = $outerLoops.Count
        HoleLoopCount = $holeLoops.Count
        LoopCount = $loops.Count
        LargestLoopPoints = $largestLoop.Count
        Svg = $svgPath
        Overlay = $overlayPath
        Comparison = $comparisonPath
    } | Format-List
}
finally {
    $bitmap.Dispose()
}
