package openfl.text;

import flash.display.Bitmap;
import flash.display.BitmapData;
import flash.display.Graphics;
import flash.display.Sprite;
import flash.events.Event;
import flash.geom.Matrix;
import flash.geom.Point;
import flash.geom.Rectangle;
import flash.geom.ColorTransform;
import openfl.text.BitmapFont;
import openfl.text.BitmapFontGlyphFrame;
import openfl.text.BitmapTextFieldAlign;
import openfl.display.PixelSnapping;
import openfl.display.Tileset;
import openfl.display.Tilemap;
import openfl.display.Tile;

@:access(openfl.geom.Matrix)
@:access(openfl.geom.Rectangle)
@:access(openfl.geom.ColorTransform)
class BitmapTextField extends Sprite
{
	static private var tempColorTransform:ColorTransform = new ColorTransform();

	private var __lines:Array<String> = [];
	private var __linesWidth:Array<Float> = [];
	private var __fieldWidth:Float = 100.0;
	private var __fieldHeight:Float = 100.0;
	private var __textWidth:Float = 0.0;
	private var __textHeight:Float = 0.0;
	private var __numLines:Int = 0;
	private var __layoutDirty:Bool = true;
	private var __graphicsDirty:Bool = true;
	private var __tilemap:Tilemap;

	public var font(default, set):BitmapFont;
	public var text(default, set):String = "";
	public var alignment(default, set):BitmapTextFieldAlign = LEFT;
	public var alignV(default, set):BitmapTextFieldAlign = TOP;
	public var lineSpacing(default, set):Float = 0;
	public var letterSpacing(default, set):Float = 0;
	public var wrap(default, set):BitmapTextFieldWrapMode = NONE;
	public var autoSize(default, set):Bool = false;
	public var autoSizeV(default, set):Bool = true;
	public var padding(default, set):Float = 0;
	public var textColor(default, set):Null<UInt> = null;
	public var backgroundColor(default, set):Null<UInt> = null;
	public var borderColor(default, set):Null<UInt> = null;
	public var borderWidth(default, set):Float = 1;
	public var size(default, set):Float = 1;
	public var smoothing(default, set):Bool = true;
	public var numSpacesInTab(default, set):Int = 4;
	public var pixelSnapping(default, set):PixelSnapping = AUTO;
	public var useKerning(default, set):Bool = true;

	public var outlineColor:Null<UInt> = null;
	public var outlineWidth:Float = 0.0;
	public var weight:Float = 1.0;

	public var textWidth(get, null):Float;
	public var textHeight(get, null):Float;
	public var numLines(get, null):Int;
	public var lineHeight(get, null):Float;
	public var spaceWidth(get, null):Float;
	public var tabWidth(get, null):Float;
	public var paddingAndBorder(get, null):Float;

	/**
	 * Constructs a new text field component.
	 * @param font	optional parameter for component's font prop
	 * @param text	optional parameter for component's text
	 */
	public function new(?userFont:BitmapFont, text:String = "", pixelSnapping:PixelSnapping = AUTO, smoothing:Bool = true)
	{
		super();

		if (userFont == null)
		{
			font = BitmapFont.getDefaultFont();
		}

		font = userFont;

		this.text = text;
		this.pixelSnapping = pixelSnapping;
		this.smoothing = smoothing;
	}

	private function set_textColor(value:UInt):UInt
	{
		if (textColor != value)
		{
			textColor = value;
			__graphicsDirty = true;
		}

		return value;
	}

	private function set_text(value:String):String
	{
		if (value != text && value != null)
		{
			text = value;
			__layoutDirty = true;
		}

		return value;
	}

	private function __updateLayout():Void
	{
		if (!__layoutDirty) return;

		__lines = [];
		__linesWidth = [];

		var maxWidth = autoSize ? Math.POSITIVE_INFINITY : (__fieldWidth - 2 * paddingAndBorder);

		var line = new StringBuf();
		var lineWidth = Math.abs(font.minOffsetX) * size;
		var lastBreakIndex = -1;
		var lastBreakWidth = 0.0;
		var lastBreakLineLength = 0;
		var lastBreakStartIndex = -1;
		var needsBreak = false;

		var len = text.length;
		var i = 0;
		var prevCharCode:Int = -1;
		var charCode:Int = -1;
		var charWidth:Float;
		var isWhiteSpace:Bool;
		var isBreakable:Bool;
		var nextWidth:Float;
		var kerning:Float;

		while (i < len)
		{
			charCode = text.charCodeAt(i);
			isWhiteSpace = false;

			switch (charCode)
			{
				case BitmapFont.newLineCode:
					__lines.push(line.toString());
					__linesWidth.push(lineWidth);
					line = new StringBuf();
					lineWidth = Math.abs(font.minOffsetX) * size;
					lastBreakIndex = -1;
					prevCharCode = -1;
					i++;
					continue;

				case BitmapFont.spaceCode:
					isWhiteSpace = true;
					charWidth = spaceWidth;

				case BitmapFont.tabCode:
					isWhiteSpace = true;
					charWidth = tabWidth;

				default:
					charWidth = font.glyphs.exists(charCode) ? font.glyphs.get(charCode).xadvance * size : 0.0;
			}

			kerning = font.getKerning(prevCharCode, charCode);
			nextWidth = lineWidth + charWidth + letterSpacing * size;
			if (useKerning)
			{
				nextWidth += kerning * size;
			}

			needsBreak = nextWidth > maxWidth;
			isBreakable = false;

			switch (wrap)
			{
				case CHAR:
					isBreakable = true;
				case WORD:
					isBreakable = isWhiteSpace;
				default:
					needsBreak = false;
			}

			if (isBreakable)
			{
				lastBreakIndex = i;
				lastBreakWidth = lineWidth;
				lastBreakLineLength = line.length;
			}

			if (needsBreak)
			{
				__lines.push(line.toString().substr(0, lastBreakLineLength));
				__linesWidth.push(lastBreakWidth);
				line = new StringBuf();
				lineWidth = Math.abs(font.minOffsetX) * size;
				i = lastBreakIndex + 1;
				lastBreakIndex = -1;
				prevCharCode = -1;
				continue;
			}

			line.addChar(charCode);
			lineWidth = nextWidth;
			i++;
			prevCharCode = charCode;
		}

		if (line.length > 0)
		{
			__lines.push(line.toString());
			__linesWidth.push(lineWidth);
		}

		__textWidth = 0.0;
		__numLines = __lines.length;

		for (i in 0...__numLines)
		{
			__textWidth = Math.max(__textWidth, __linesWidth[i]);
		}
		__textHeight = (lineHeight + lineSpacing) * __numLines - lineSpacing;

		__layoutDirty = false;
		__graphicsDirty = true;

		var p = paddingAndBorder;
		if (autoSizeV)
		{
			__fieldHeight = __textHeight + 2 * p;
		}
		if (autoSize)
		{
			__fieldWidth = __textWidth + 2 * p;
		}
	}

	/**
	 * Internal method for updating the view of the text component
	 */
	private function __updateGraphics():Void
	{
		if (!__graphicsDirty) return;

		graphics.clear();

		if (backgroundColor != null || borderColor != null)
		{
			if (backgroundColor != null) graphics.beginFill(backgroundColor & 0x00FFFFFF, ((backgroundColor >> 24) & 0xFF) / 255);
			if (borderColor != null) graphics.lineStyle(1, borderColor & 0x00FFFFFF, ((borderColor >> 24) & 0xFF) / 255);
			graphics.drawRect(0, 0, __fieldWidth, __fieldHeight);
		}

		var w = Math.ceil(__fieldWidth);
		var h = Math.ceil(__fieldHeight);

		if (__tilemap == null)
		{
			__tilemap = new Tilemap(w, h, font.tileset, smoothing);
			addChild(__tilemap);
		}
		else
		{
			__tilemap.removeTiles();
			__tilemap.width = w;
			__tilemap.height = h;
			__tilemap.smoothing = smoothing;
		}

		if (textColor != null)
		{
			var color:UInt = textColor;
			var rgb = color & 0x00FFFFFF;
			var a = ((color >> 24) & 0xFF) / 255;
			tempColorTransform.color = color;
			tempColorTransform.alphaMultiplier = a;
		}
		else
		{
			tempColorTransform.__identity();
		}

		__tilemap.transform.colorTransform = tempColorTransform;
		__tilemap.pixelSnapping = pixelSnapping;
		// __tilemap.shader = __defaultBitmapTextFieldShader;

		if (size > 0)
		{
			var line:String;
			var lineWidth:Float;
			var ox:Float, oy:Float;
			var glyph:BitmapFontGlyphFrame;
			var charCode:Int;
			var prevCharCode:Int;
			var cx:Float, cy:Float;
			var p = paddingAndBorder;
			var lineLength:Int;
			var kerning:Float = 0.0;

			switch (alignV)
			{
				case MIDDLE:
					oy = (__fieldHeight - __textHeight) / 2 - p;

				case BOTTOM:
					oy = (__fieldHeight - __textHeight) - p;

				default:
					oy = p;
			}

			for (i in 0...__numLines)
			{
				line = __lines[i];
				lineWidth = __linesWidth[i];

				ox = Math.abs(font.minOffsetX) * size;

				switch (alignment)
				{
					case CENTER:
						ox += (__fieldWidth - lineWidth) / 2 - p;

					case RIGHT:
						ox += (__fieldWidth - lineWidth) - p;

					default:
						ox += p;
				}

				cx = ox;
				cy = oy;

				lineLength = line.length;
				prevCharCode = -1;

				for (i in 0...lineLength)
				{
					charCode = line.charCodeAt(i);
					kerning = font.getKerning(prevCharCode, charCode);

					switch (charCode)
					{
						case BitmapFont.spaceCode:
							cx += spaceWidth;

						case BitmapFont.tabCode:
							cx += tabWidth;

						default:
							glyph = font.glyphs.get(charCode);
							if (glyph != null)
							{
								var tile = new Tile(glyph.tileID);
								tile.x = cx + glyph.xoffset * size;
								tile.y = cy + glyph.yoffset * size;
								tile.scaleX = tile.scaleY = size;
								cx += glyph.xadvance * size;
								__tilemap.addTile(tile);
							}
					}

					cx += letterSpacing * size;
					if (useKerning)
					{
						cx += kerning * size;
					}

					prevCharCode = charCode;
				}

				oy += (font.lineHeight * size + lineSpacing);
			}
		}

		__graphicsDirty = false;
	}

	#if !flash
	override function set_width(value:Float):Float
	#else
	@:setter(width) function set_width(value:Float):Void
	#end
	{
		if (value != width)
		{
			__fieldWidth = value;
			__layoutDirty = true;
		}
		#if !flash
		return value;
		#end
	}

	#if !flash
	override function set_height(value:Float):Float
	#else
	@:setter(height) function set_height(value:Float):Void
	#end
	{
		if (value != height)
		{
			__fieldHeight = value;
			__layoutDirty = true;
		}
		#if !flash
		return value;
		#end
	}

	private function set_alignment(value:BitmapTextFieldAlign):BitmapTextFieldAlign
	{
		if (alignment != value)
		{
			alignment = value;
			__graphicsDirty = true;
		}

		return value;
	}

	private function set_alignV(value:BitmapTextFieldAlign):BitmapTextFieldAlign
	{
		if (alignV != value)
		{
			alignV = value;
			__graphicsDirty = true;
		}

		return value;
	}

	private function set_font(value:BitmapFont):BitmapFont
	{
		if (font != value && value != null)
		{
			font = value;
			__layoutDirty = true;
		}

		return value;
	}

	private function set_lineSpacing(value:Float):Float
	{
		if (lineSpacing != value)
		{
			lineSpacing = value;
			__graphicsDirty = true;
		}

		return lineSpacing;
	}

	private function set_letterSpacing(value:Float):Float
	{
		if (value != letterSpacing)
		{
			letterSpacing = value;
			__layoutDirty = true;
		}

		return letterSpacing;
	}

	private function set_wrap(value:BitmapTextFieldWrapMode):BitmapTextFieldWrapMode
	{
		if (wrap != value)
		{
			wrap = value;
			__layoutDirty = true;
		}
		return wrap;
	}

	private function set_autoSize(value:Bool):Bool
	{
		if (autoSize != value)
		{
			autoSize = value;
			__layoutDirty = true;
		}
		return autoSize;
	}

	private function set_autoSizeV(value:Bool):Bool
	{
		if (autoSizeV != value)
		{
			autoSizeV = value;
			__layoutDirty = true;
		}
		return autoSizeV;
	}

	private function set_size(value:Float):Float
	{
		value = Math.abs(value);
		if (value != size)
		{
			size = value;
			__layoutDirty = true;
		}
		return value;
	}

	private function set_padding(value:Float):Float
	{
		if (value != padding)
		{
			padding = value;
			__layoutDirty = true;
		}

		return value;
	}

	private function set_numSpacesInTab(value:Int):Int
	{
		if (numSpacesInTab != value && value > 0)
		{
			numSpacesInTab = value;
			__layoutDirty = true;
		}
		return value;
	}

	private function set_pixelSnapping(value:PixelSnapping):PixelSnapping
	{
		if (pixelSnapping != value)
		{
			pixelSnapping = value;
			__graphicsDirty = true;
		}
		return value;
	}

	private function set_useKerning(value:Bool):Bool
	{
		if (useKerning != value)
		{
			useKerning = value;
			__layoutDirty = true;
		}
		return value;
	}

	private function set_backgroundColor(value:Null<UInt>):Null<UInt>
	{
		if (backgroundColor != value)
		{
			backgroundColor = value;
			__graphicsDirty = true;
		}
		return value;
	}

	private function set_borderColor(value:Null<UInt>):Null<UInt>
	{
		if (borderColor != value)
		{
			borderColor = value;
			__graphicsDirty = true;
		}
		return value;
	}

	private function set_borderWidth(value:Float):Float
	{
		value = Math.abs(value);
		if (borderWidth != value)
		{
			borderWidth = value;
			__layoutDirty = true;
		}
		return value;
	}

	private function get_textWidth():Float
	{
		__updateLayout();
		return __textWidth;
	}

	private function get_textHeight():Float
	{
		__updateLayout();
		return __textHeight;
	}

	private function get_numLines():Int
	{
		__updateLayout();
		return __numLines;
	}

	private inline function get_lineHeight():Float
	{
		return font.lineHeight * size;
	}

	private inline function get_tabWidth():Float
	{
		return font.spaceWidth * numSpacesInTab * size;
	}

	private inline function get_spaceWidth():Float
	{
		return font.spaceWidth * size;
	}

	private inline function get_paddingAndBorder():Float
	{
		if (borderColor != null) return padding * borderWidth;
		return padding;
	}

	private function set_smoothing(value:Bool):Bool
	{
		if (smoothing != value)
		{
			__graphicsDirty = true;
		}

		return smoothing = value;
	}

	@:noCompletion private override function __getBounds(rect:Rectangle, matrix:Matrix, exStroke:Bool = false):Void
	{
		__updateLayout();

		var bounds = Rectangle.__pool.get();
		bounds.setTo(0, 0, __fieldWidth, __fieldHeight);
		bounds.__transform(bounds, matrix);

		rect.__expand(bounds.x, bounds.y, bounds.width, bounds.height);

		Rectangle.__pool.release(bounds);
	}

	@:noCompletion private override function __getRenderBounds(rect:Rectangle, matrix:Matrix):Void
	{
		__getBounds(rect, matrix);
	}

	@:noCompletion override private function __enterFrame(deltaTime:Int):Void
	{
		__updateLayout();
		__updateGraphics();
		super.__enterFrame(deltaTime);
	}
}
