package openfl.utils;

class ColorUtil
{
	public static inline function argbToABGR(color:Int):Int
	{
		var a = (color >> 24) & 0xFF;
		var r = (color >> 16) & 0xFF;
		var g = (color >> 8) & 0xFF;
		var b = color & 0xFF;
		return (a << 24) | (b << 16) | (g << 8) | r; // ABGR
	}

	public static inline function rgbToRGBA(color:Int, alpha:Float):Int
	{
		var r = (color >> 16) & 0xFF;
		var g = (color >> 8) & 0xFF;
		var b = color & 0xFF;
		var a = Std.int(alpha * 255) & 0xFF;
		return (a << 24) | (b << 16) | (g << 8) | r; // ABGR
	}
}
