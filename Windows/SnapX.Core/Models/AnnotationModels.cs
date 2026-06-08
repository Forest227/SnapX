namespace SnapX.Core.Models;

public enum AnnotationTool
{
    Rectangle,
    Highlight,
    Text,
    Arrow,
    Line,
    Pen,
    Mosaic,
}

public enum AnnotationColor
{
    Red,
    Green,
    Orange,
    Yellow,
    Blue,
}

public sealed record AnnotationStroke(
    AnnotationTool Tool,
    SnapPoint Start,
    SnapPoint End,
    AnnotationColor Color,
    double Width,
    string? Text = null,
    IReadOnlyList<SnapPoint>? Points = null);

public sealed record AnnotationDocument(
    SnapSize ImageSize,
    IReadOnlyList<AnnotationStroke> Strokes)
{
    public static AnnotationDocument Empty(SnapSize imageSize) => new(imageSize, Array.Empty<AnnotationStroke>());
}
