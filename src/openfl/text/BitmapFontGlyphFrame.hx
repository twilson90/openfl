package openfl.text;

import flash.geom.Rectangle;
import openfl.display.Tile;

class BitmapFontGlyphFrame
{
	/**
	 * Bitmap font which this glyph frame belongs to.
	 */
	public var parent:BitmapFont;

	public var charCode:Int;

	/**
	 * x offset to draw symbol with
	 */
	public var xoffset:Int;

	/**
	 * y offset to draw symbol with
	 */
	public var yoffset:Int;

	/**
	 * real width of symbol
	 */
	public var xadvance:Int;

	/**
	 * Source image area which contains image of this glyph
	 */
	public var rect:Rectangle;

	public var width(get, never):Int;
	public var height(get, never):Int;

	/**
	 * tile id in parent's tileSheet
	 */
	public var tileID:Int;

	public var tile:Tile;

	public function new(parent:BitmapFont)
	{
		this.parent = parent;
	}

	public function dispose():Void
	{
		rect = null;
	}

	/**
	 * Returns width of this glyph.
	 */
	public function get_width():Int
	{
		return Std.int(rect.width);
	}

	/**
	 * Returns height of this glyph.
	 */
	public function get_height():Int
	{
		return Std.int(rect.height);
	}
}
