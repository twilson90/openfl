package openfl.text;

import haxe.xml.Access;
import openfl.display.BitmapData;
import openfl.display.Graphics;
import openfl.display.DistanceFieldType;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.display.Tileset;
import openfl.display.Tile;
import openfl.errors.Error;

/**
 * Holds information and bitmap glyphs for a bitmap font.
 */
class BitmapFont
{
	public static inline var spaceCode:Int = " ".code;
	public static inline var tabCode:Int = "\t".code;
	public static inline var newLineCode:Int = "\n".code;
	public static inline var hyphenCode:Int = "-".code;
	public static inline var defaultFontKey:String = "defaultFontKey";
	private static inline var defaultFontData:String = " 36000000000000000000!26101010001000\"46101010100000000000000000#66010100111110010100111110010100000000$56001000111011000001101110000100%66100100000100001000010000010010000000&66011000100000011010100100011010000000'26101000000000(36010100100100010000)36100010010010100000*46000010100100101000000000+46000001001110010000000000,36000000000000010100-46000000001110000000000000.26000000001000/66000010000100001000010000100000000000056011001001010010100100110000000156011000010000100001000010000000256111000001001100100001111000000356111000001001100000101110000000456100101001010010011100001000000556111101000011100000101110000000656011001000011100100100110000000756111000001000010001100001000000856011001001001100100100110000000956011001001010010011100001000000:26001000100000;26001000101000<46001001001000010000100000=46000011100000111000000000>46100001000010010010000000?56111000001001100000000100000000@66011100100010101110101010011100000000A56011001001010010111101001000000B56111001001011100100101110000000C56011001001010000100100110000000D56111001001010010100101110000000E56111101000011000100001111000000F56111101000010000110001000000000G56011001000010110100100111000000H56100101001011110100101001000000I26101010101000J56000100001000010100100110000000K56100101001010010111001001000000L46100010001000100011100000M66100010100010110110101010100010000000N56100101001011010101101001000000O56011001001010010100100110000000P56111001001010010111001000000000Q56011001001010010100100110000010R56111001001010010111001001000000S56011101000001100000101110000000T46111001000100010001000000U56100101001010010100100110000000V56100101001010010101000100000000W66100010100010101010110110100010000000X56100101001001100100101001000000Y56100101001010010011100001001100Z56111100001001100100001111000000[36110100100100110000}46110001000010010011000000]36110010010010110000^46010010100000000000000000_46000000000000000011110000'26101000000000a56000000111010010100100111000000b56100001110010010100101110000000c46000001101000100001100000d56000100111010010100100111000000e56000000110010110110000110000000f46011010001000110010000000g5700000011001001010010011100001001100h56100001110010010100101001000000i26100010101000j37010000010010010010100k56100001001010010111001001000000l26101010101000m66000000111100101010101010101010000000n56000001110010010100101001000000o56000000110010010100100110000000p5700000111001001010010111001000010000q5700000011101001010010011100001000010r46000010101100100010000000s56000000111011000001101110000000t46100011001000100001100000u56000001001010010100100111000000v56000001001010010101000100000000w66000000101010101010101010011110000000x56000001001010010011001001000000y5700000100101001010010011100001001100z56000001111000100010001111000000{46011001001000010001100000|26101010101000}46110001000010010011000000~56010101010000000000000000000000\\46111010101010101011100000";
	public static inline var DEFAULT_GLYPHS:String = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";

	private static var POINT:Point = new Point();
	private static var MATRIX:Matrix = new Matrix();
	private static var COLOR_TRANSFORM:ColorTransform = new ColorTransform();
	private static var fonts:Map<String, BitmapFont> = new Map<String, BitmapFont>();

	public var size(default, null):Int = 0;
	public var lineHeight(default, null):Int = 0;
	public var bold:Bool = false;
	public var italic:Bool = false;
	public var distanceFieldType:DistanceFieldType = NONE;
	public var distanceRange:Float = 0.0;
	public var fontName:String;

	public var minOffsetX:Int = 0;
	public var spaceWidth:Int = 0;
	public var bitmap:BitmapData;
	public var glyphs:Map<Int, BitmapFontGlyphFrame>;
	public var tileset:Tileset;

	private var kernings:Map<Int, Int> = new Map<Int, Int>();

	public var hasKernings(default, null):Bool = false;

	/**
	 * Stores a font for global use using an identifier.
	 * @param	fontKey		String identifer for the font.
	 * @param	font		Font to store.
	 */
	public static function set(fontKey:String, font:BitmapFont):Void
	{
		if (!fonts.exists(fontKey))
		{
			fonts.set(fontKey, font);
		}
	}

	/**
	 * Retrieves a font previously stored.
	 * @param	fontKey		Identifier of font to fetch.
	 * @return	Stored font, or null if no font was found.
	 */
	public static function get(fontKey:String):BitmapFont
	{
		return fonts.get(fontKey);
	}

	/**
	 * Removes font with provided fontKey and disposes it.
	 * @param	fontKey		The name of font to remove.
	 */
	public static function remove(fontKey):Void
	{
		var font:BitmapFont = fonts.get(fontKey);
		fonts.remove(fontKey);

		if (font != null)
		{
			font.dispose();
		}
	}

	/**
	 * Clears fonts storage and disposes all fonts.
	 */
	public static function clearFonts():Void
	{
		for (font in fonts)
		{
			font.dispose();
		}

		fonts = new Map<String, BitmapFont>();
	}

	/**
	 * Retrieves default BitmapFont.
	 */
	public static function getDefaultFont():BitmapFont
	{
		var font:BitmapFont = get(defaultFontKey);

		if (font != null)
		{
			return font;
		}

		var letters:String = "";
		var bd:BitmapData = new BitmapData(700, 9, true, 0xFF888888);

		var letterPos:Int = 0;
		var i:Int = 0;

		while (i < defaultFontData.length)
		{
			letters += defaultFontData.substr(i, 1);

			var gw:Int = Std.parseInt(defaultFontData.substr(++i, 1));
			var gh:Int = Std.parseInt(defaultFontData.substr(++i, 1));

			for (py in 0...gh)
			{
				for (px in 0...gw)
				{
					i++;

					if (defaultFontData.substr(i, 1) == "1")
					{
						bd.setPixel32(1 + letterPos * 7 + px, 1 + py, 0xFF000000);
					}
					else
					{
						bd.setPixel32(1 + letterPos * 7 + px, 1 + py, 0x00000000);
					}
				}
			}

			i++;
			letterPos++;
		}

		return fromXNA(defaultFontKey, bd, letters);
	}

	private static inline function makeKey(first:Int, second:Int):Int
	{
		if (first > 0xffff || second > 0xffff)
		{
			throw new Error("Kerning keys must be 16-bit values.");
		}
		return first << 16 | second;
	}

	/**
	 * Creates and stores new bitmap font using specified source image.
	 */
	public function new(name:String, bitmap:BitmapData)
	{
		this.bitmap = bitmap;
		this.fontName = name;
		tileset = new Tileset(bitmap);
		glyphs = new Map<Int, BitmapFontGlyphFrame>();
		set(name, this);
	}

	/**
	 * Destroys this font object.
	 * WARNING: it disposes source image also.
	 */
	public function dispose():Void
	{
		if (bitmap != null)
		{
			bitmap.dispose();
		}

		bitmap = null;
		tileset = null;
		glyphs = null;
		fontName = null;
	}

	/**
	 * Loads font data in AngelCode's format.
	 *
	 * @param	Source		Font image source.
	 * @param	Data		XML font data.
	 * @return	Generated bitmap font object.
	 */
	public static function fromAngelCode(source:BitmapData, xml:Xml):BitmapFont
	{
		var access = new Access(xml.firstElement());
		var fontName = Std.string(access.node.info.att.face);

		var font:BitmapFont = get(fontName);

		if (font != null)
		{
			return font;
		}

		font = new BitmapFont(fontName, source);
		font.lineHeight = Std.parseInt(access.node.common.att.lineHeight);
		font.size = Std.parseInt(access.node.info.att.size);
		font.fontName = Std.string(access.node.info.att.face);
		font.bold = (Std.parseInt(access.node.info.att.bold) != 0);
		font.italic = (Std.parseInt(access.node.info.att.italic) != 0);

		var frame:Rectangle;
		var glyph:String;
		var charCode:Int;
		var xOffset:Int, yOffset:Int, xAdvance:Int;
		var frameHeight:Int;

		if (access.hasNode.distanceField)
		{
			var distanceField = access.node.distanceField;
			font.distanceFieldType = switch (distanceField.att.fieldType)
			{
				case "msdf": MSDF;
				default: SDF;
			}

			font.distanceRange = Std.parseFloat(distanceField.att.distanceRange);
		}

		var chars = access.node.chars;

		for (char in chars.nodes.char)
		{
			frame = new Rectangle();
			frame.x = Std.parseInt(char.att.x);
			frame.y = Std.parseInt(char.att.y);
			frame.width = Std.parseInt(char.att.width);
			frameHeight = Std.parseInt(char.att.height);
			frame.height = frameHeight;

			xOffset = char.has.xoffset ? Std.parseInt(char.att.xoffset) : 0;
			yOffset = char.has.yoffset ? Std.parseInt(char.att.yoffset) : 0;
			xAdvance = char.has.xadvance ? Std.parseInt(char.att.xadvance) : 0;

			font.minOffsetX = (font.minOffsetX > xOffset) ? xOffset : font.minOffsetX;

			glyph = null;
			charCode = -1;

			if (char.has.letter)
			{
				glyph = char.att.letter;
			}
			else if (char.has.id)
			{
				charCode = Std.parseInt(char.att.id);
			}

			if (charCode == -1 && glyph == null)
			{
				throw 'Invalid font xml data!';
			}

			if (glyph != null)
			{
				glyph = switch (glyph)
				{
					case "space": ' ';
					case "&quot;": '"';
					case "&amp;": '&';
					case "&gt;": '>';
					case "&lt;": '<';
					default: glyph;
				}

				charCode = glyph.charCodeAt(0);
			}

			font.addGlyphFrame(charCode, frame, xOffset, yOffset, xAdvance);

			if (charCode == spaceCode)
			{
				font.spaceWidth = xAdvance;
			}
			else
			{
				font.lineHeight = (font.lineHeight > frameHeight + yOffset) ? font.lineHeight : frameHeight + yOffset;
			}
		}

		if (access.hasNode.kernings)
		{
			for (kerning in access.node.kernings.nodes.kerning)
			{
				font.hasKernings = true;
				var first = Std.parseInt(kerning.att.first);
				var second = Std.parseInt(kerning.att.second);
				var key = makeKey(first, second);
				var amount = Std.parseInt(kerning.att.amount);
				font.kernings.set(key, amount);
			}
		}

		return font;
	}

	/**
	 * Load bitmap font in XNA/Pixelizer format.
	 * I took this method from HaxePunk engine.
	 *
	 * @param	key				Name for this font.
	 * @param	source			Source image for this font.
	 * @param	letters			String of glyphs contained in the source image, in order (ex. " abcdefghijklmnopqrstuvwxyz"). Defaults to DEFAULT_GLYPHS.
	 * @param	glyphBGColor	An additional background color to remove. Defaults to 0xFF202020, often used for glyphs background.
	 * @return	Generated bitmap font object.
	 */
	public static function fromXNA(key:String, source:BitmapData, letters:String = null, glyphBGColor:Int = 0x00000000):BitmapFont
	{
		var font:BitmapFont = get(key);

		if (font != null)
		{
			return font;
		}

		font = new BitmapFont(key, source);
		font.fontName = key;

		letters = (letters == null) ? DEFAULT_GLYPHS : letters;

		var bmd:BitmapData = source;
		var globalBGColor:Int = bmd.getPixel(0, 0);
		var cy:Int = 0;
		var cx:Int;
		var letterIdx:Int = 0;
		var charCode:Int;
		var numLetters:Int = letters.length;
		var rect:Rectangle;
		var xAdvance:Int;

		while (cy < bmd.height && letterIdx < numLetters)
		{
			var rowHeight:Int = 0;
			cx = 0;

			while (cx < bmd.width && letterIdx < numLetters)
			{
				if (Std.int(bmd.getPixel(cx, cy)) != globalBGColor)
				{
					// found non bg pixel
					var gx:Int = cx;
					var gy:Int = cy;

					// find width and height of glyph
					while (Std.int(bmd.getPixel(gx, cy)) != globalBGColor)
						gx++;
					while (Std.int(bmd.getPixel(cx, gy)) != globalBGColor)
						gy++;

					var gw:Int = gx - cx;
					var gh:Int = gy - cy;

					charCode = letters.charCodeAt(letterIdx);

					rect = new Rectangle(cx, cy, gw, gh);

					xAdvance = gw;

					font.addGlyphFrame(charCode, rect, 0, 0, xAdvance);

					if (charCode == spaceCode)
					{
						font.spaceWidth = xAdvance;
					}

					// store max size
					if (gh > rowHeight) rowHeight = gh;
					if (gh > font.size) font.size = gh;

					// go to next glyph
					cx += gw;
					letterIdx++;
				}

				cx++;
			}

			// next row
			cy += (rowHeight + 1);
		}

		font.lineHeight = font.size;

		// remove background color
		POINT.x = POINT.y = 0;
		var bgColor32:Int = bmd.getPixel32(0, 0);
		#if !js
		bmd.threshold(bmd, bmd.rect, POINT, "==", bgColor32, 0x00000000, 0xFFFFFFFF, true);
		#else
		replaceColor(bmd, bgColor32, 0x00000000);
		#end
		if (glyphBGColor != 0x00000000)
		{
			#if !js
			bmd.threshold(bmd, bmd.rect, POINT, "==", glyphBGColor, 0x00000000, 0xFFFFFFFF, true);
			#else
			replaceColor(bmd, glyphBGColor, 0x00000000);
			#end
		}

		return font;
	}

	public static function replaceColor(bitmapData:BitmapData, color:Int, newColor:Int):BitmapData
	{
		var row:Int = 0;
		var column:Int = 0;
		var rows:Int = bitmapData.height;
		var columns:Int = bitmapData.width;
		bitmapData.lock();
		while (row < rows)
		{
			column = 0;
			while (column < columns)
			{
				if (bitmapData.getPixel32(column, row) == cast color)
				{
					bitmapData.setPixel32(column, row, newColor);
				}
				column++;
			}
			row++;
		}
		bitmapData.unlock();

		return bitmapData;
	}

	/**
	 * Loads monospace bitmap font.
	 *
	 * @param	key			Name for this font.
	 * @param	source		Source image for this font.
	 * @param	letters		The characters used in the font set, in display order. You can use the TEXT_SET consts for common font set arrangements.
	 * @param	charSize	The size of each character in the font set.
	 * @param	region		The region of image to use for the font. Default is null which means that the whole image will be used.
	 * @param	spacing		Spaces between characters in the font set. Default is null which means no spaces.
	 * @return	Generated bitmap font object.
	 */
	public static function fromMonospace(key:String, source:BitmapData, letters:String = null, charSize:Point, region:Rectangle = null,
			spacing:Point = null):BitmapFont
	{
		var font:BitmapFont = get(key);
		if (font != null) return font;

		letters = (letters == null) ? DEFAULT_GLYPHS : letters;

		region = (region == null) ? source.rect : region;

		if (region.width == 0 || region.right > source.width)
		{
			region.width = source.width - region.x;
		}

		if (region.height == 0 || region.bottom > source.height)
		{
			region.height = source.height - region.y;
		}

		spacing = (spacing == null) ? new Point(0, 0) : spacing;

		var bitmapWidth:Int = Std.int(region.width);
		var bitmapHeight:Int = Std.int(region.height);

		var startX:Int = Std.int(region.x);
		var startY:Int = Std.int(region.y);

		var xSpacing:Int = Std.int(spacing.x);
		var ySpacing:Int = Std.int(spacing.y);

		var charWidth:Int = Std.int(charSize.x);
		var charHeight:Int = Std.int(charSize.y);

		var spacedWidth:Int = charWidth + xSpacing;
		var spacedHeight:Int = charHeight + ySpacing;

		var numRows:Int = (charHeight == 0) ? 1 : Std.int((bitmapHeight + ySpacing) / spacedHeight);
		var numCols:Int = (charWidth == 0) ? 1 : Std.int((bitmapWidth + xSpacing) / spacedWidth);

		font = new BitmapFont(key, source);
		font.fontName = key;
		font.lineHeight = font.size = charHeight;

		var charRect:Rectangle;
		var xAdvance:Int = charWidth;
		font.spaceWidth = xAdvance;
		var letterIndex:Int = 0;
		var numLetters:Int = letters.length;

		for (j in 0...(numRows))
		{
			for (i in 0...(numCols))
			{
				charRect = new Rectangle(startX + i * spacedWidth, startY + j * spacedHeight, charWidth, charHeight);
				font.addGlyphFrame(letters.charCodeAt(letterIndex), charRect, 0, 0, xAdvance);

				letterIndex++;

				if (letterIndex >= numLetters)
				{
					return font;
				}
			}
		}

		return font;
	}

	/**
	 * Internal method which creates and add glyph frames into this font.
	 *
	 * @param	charCode		Char code for glyph frame.
	 * @param	frame			Glyph area from source image.
	 * @param	offsetX			X offset before rendering this glyph.
	 * @param	offsetX			Y offset before rendering this glyph.
	 * @param	xAdvance		How much cursor will jump after this glyph.
	 */
	private function addGlyphFrame(charCode:Int, frame:Rectangle, offsetX:Int = 0, offsetY:Int = 0, xAdvance:Int = 0):Void
	{
		if (frame.width == 0 || frame.height == 0 || glyphs.get(charCode) != null) return;

		var glyphFrame:BitmapFontGlyphFrame = new BitmapFontGlyphFrame(this);
		glyphFrame.charCode = charCode;
		glyphFrame.xoffset = offsetX;
		glyphFrame.yoffset = offsetY;
		glyphFrame.xadvance = xAdvance;
		glyphFrame.rect = frame;
		glyphFrame.tileID = tileset.addRect(frame);
		glyphs.set(charCode, glyphFrame);
	}

	public function getKerning(first:Int, second:Int):Int
	{
		var key = makeKey(first, second);
		return kernings.exists(key) ? kernings.get(key) : 0;
	}
}
