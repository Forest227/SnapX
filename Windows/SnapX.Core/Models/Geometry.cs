namespace SnapX.Core.Models;

public readonly record struct SnapPoint(double X, double Y);

public readonly record struct SnapSize(double Width, double Height)
{
    public bool IsEmpty => Width <= 0 || Height <= 0;
}

public readonly record struct SnapRect(double X, double Y, double Width, double Height)
{
    public bool IsEmpty => Width <= 0 || Height <= 0;

    public SnapPoint Origin => new(X, Y);

    public SnapSize Size => new(Width, Height);

    public double Left => X;

    public double Top => Y;

    public double Right => X + Width;

    public double Bottom => Y + Height;

    public static SnapRect FromPoints(SnapPoint a, SnapPoint b)
    {
        var x = Math.Min(a.X, b.X);
        var y = Math.Min(a.Y, b.Y);
        return new SnapRect(x, y, Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));
    }
}
