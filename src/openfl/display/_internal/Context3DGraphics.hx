package openfl.display._internal;

#if !flash
import haxe.ds.IntMap;
import haxe.ds.StringMap;
import haxe.io.Bytes;
import openfl.display.BitmapData;
import openfl.display.CapsStyle;
import openfl.display.Graphics;
import openfl.display.JointStyle;
import openfl.display.LineScaleMode;
import openfl.display.OpenGLRenderer;
import openfl.display._internal.geom.PolyLineTesselator;
import openfl.display._internal.geom.Tess2;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DClearMask;
import openfl.display3D.IndexBuffer3D;
import openfl.display3D.VertexBuffer3D;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.utils.ArrayUtil;
import openfl.utils.ColorUtil;
import openfl.utils._internal.FastHash;
import openfl.utils._internal.LRUCache;
import openfl.utils.ObjectPool;
import openfl.utils._internal.Float32Array;
import openfl.utils._internal.UInt32Array;
#if lime
import lime.math.ARGB;
import lime.utils.ArrayBuffer;
#end

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.display3D.Context3D)
@:access(openfl.display.DisplayObject)
@:access(openfl.display.Graphics)
@:access(openfl.display.Shader)
@:access(openfl.geom.ColorTransform)
@:access(openfl.geom.Matrix)
@:access(openfl.geom.Rectangle)
@:access(openfl.display._internal.DrawContext)
@:access(openfl.display._internal.Context3DGraphicsBatchBuffer)
@:access(openfl.display._internal.Gradient)
@:access(openfl.display._internal.Contour)
@:access(openfl.display._internal.Fill)
@:access(openfl.display._internal.FillContext)
@:access(openfl.display._internal.StrokeContext)
@:access(openfl.display._internal.mesh.Polygon)
@SuppressWarnings("checkstyle:FieldDocComment")
class Context3DGraphics
{
	private static inline var DATA_PER_VERTEX:Int = 6;
	private static inline var KAPPA:Float = 0.552284749831; // 4*(√2-1)/3
	private static inline var EPSILON:Float = 1e-6;

	// private static var blankBitmapData = new BitmapData(1, 1, true, 0xffffffff);
	private static var maskRender:Bool;
	private static var ctx:DrawContext;

	public static function buildBuffer(graphics:Graphics)
	{
		var data = DrawCommandReader.__pool.get();
		data.reset(graphics.__commands);

		if (ctx == null) ctx = new DrawContext();

		ctx.init(graphics);

		if (graphics.__buffer == null) graphics.__buffer = new Context3DGraphicsBatchBuffer(graphics);
		else
			graphics.__buffer.reset();

		// var matrix = graphics.__owner.__worldTransform;
		// var scaleX = Math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b);
		// var scaleY = Math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d);

		for (type in graphics.__commands.types)
		{
			switch (type)
			{
				case MOVE_TO:
					var c = data.readMoveTo();
					var x = c.x;
					var y = c.y;

					#if openfl_gl_scale9grid
					if (graphics.__useScale9Grid)
					{
						x = graphics.__getScale9GridPositionX(x);
						y = graphics.__getScale9GridPositionY(y);
					}
					#end
					if (x != ctx.position.x || y != ctx.position.y)
					{
						ctx.moveTo(x, y);
					}

				case LINE_TO:
					var c = data.readLineTo();
					var x = c.x;
					var y = c.y;

					#if openfl_gl_scale9grid
					if (graphics.__useScale9Grid)
					{
						x = graphics.__getScale9GridPositionX(x);
						y = graphics.__getScale9GridPositionY(y);
					}
					#end

					ctx.lineTo(x, y);

				case CURVE_TO:
					var c = data.readCurveTo();
					var controlX = c.controlX;
					var controlY = c.controlY;
					var anchorX = c.anchorX;
					var anchorY = c.anchorY;

					#if openfl_gl_scale9grid
					if (graphics.__useScale9Grid)
					{
						controlX = graphics.__getScale9GridPositionX(c.controlX);
						controlY = graphics.__getScale9GridPositionY(c.controlY);
						anchorX = graphics.__getScale9GridPositionX(c.anchorX);
						anchorY = graphics.__getScale9GridPositionY(c.anchorY);
					}
					#end

					ctx.curveTo(controlX, controlY, anchorX, anchorY);

				case CUBIC_CURVE_TO:
					var c = data.readCubicCurveTo();
					var controlX1 = c.controlX1;
					var controlY1 = c.controlY1;
					var controlX2 = c.controlX2;
					var controlY2 = c.controlY2;
					var anchorX = c.anchorX;
					var anchorY = c.anchorY;

					#if openfl_gl_scale9grid
					if (graphics.__useScale9Grid)
					{
						controlX1 = graphics.__getScale9GridPositionX(c.controlX1);
						controlY1 = graphics.__getScale9GridPositionY(c.controlY1);
						controlX2 = graphics.__getScale9GridPositionX(c.controlX2);
						controlY2 = graphics.__getScale9GridPositionY(c.controlY2);
						anchorX = graphics.__getScale9GridPositionX(c.anchorX);
						anchorY = graphics.__getScale9GridPositionY(c.anchorY);
					}
					#end

					ctx.cubicCurveTo(controlX1, controlY1, controlX2, controlY2, anchorX, anchorY);

				case BEGIN_BITMAP_FILL:
					ctx.build();
					ctx.newFill();
					var c = data.readBeginBitmapFill();
					if (maskRender)
					{
						ctx.fill.fill.color = 0xffffffff;
					}
					else
					{
						ctx.fill.fill.bitmap = c.bitmap;
						ctx.fill.fill.bitmapSmooth = c.smooth;
						ctx.fill.fill.bitmapRepeat = c.repeat;
						ctx.fill.fill.matrix = c.matrix;
					}

				case BEGIN_GRADIENT_FILL:
					ctx.build();
					ctx.newFill();
					var c = data.readBeginGradientFill();
					if (maskRender)
					{
						ctx.fill.fill.color = 0xffffffff;
					}
					else
					{
						if (ctx.fill.fill.gradient == null) ctx.fill.fill.gradient = Gradient.__pool.get();
						ctx.fill.fill.gradient.setTo(c.colors, c.alphas, c.ratios, null, c.type, c.interpolationMethod, c.spreadMethod, c.focalPointRatio);
						ctx.fill.fill.matrix = c.matrix;
					}

				case BEGIN_FILL:
					ctx.build();
					ctx.newFill();
					var c = data.readBeginFill();
					var color = c.color;
					var alpha = c.alpha;
					if (maskRender)
					{
						ctx.fill.fill.color = 0xffffffff;
					}
					else
					{
						ctx.fill.fill.color = alpha >= 0.005 ? (Std.int(alpha * 255) << 24 | color) : 0;
					}

				case BEGIN_SHADER_FILL:
					ctx.build();
					ctx.newFill();
					var c = data.readBeginShaderFill();
					var shaderBuffer = c.shaderBuffer;
					if (maskRender)
					{
						ctx.fill.fill.color = 0xffffffff;
					}
					else
					{
						if (shaderBuffer != null)
						{
							ctx.fill.fill.shaderBuffer = shaderBuffer;
							for (i in 0...shaderBuffer.inputCount)
							{
								if (shaderBuffer.inputRefs[i].name == "bitmap")
								{
									ctx.fill.fill.bitmap = shaderBuffer.inputs[i];
									ctx.fill.fill.matrix = c.matrix;
									break;
								}
							}
						}
					}

				case END_FILL:
					ctx.build();
					ctx.clearFill();

				case LINE_STYLE:
					var c = data.readLineStyle();
					if (!maskRender)
					{
						var color = c.color;
						var alpha = c.alpha;
						var thickness = c.thickness;
						var caps = c.caps;
						var joints = c.joints;
						var miterLimit = c.miterLimit;
						var scaleMode = c.scaleMode;

						ctx.newStroke();
						ctx.stroke.fill.color = alpha >= 0.005 ? (Std.int(alpha * 255) << 24 | color) : 0;
						ctx.stroke.thickness = thickness;
						ctx.stroke.caps = caps;
						ctx.stroke.joints = joints;
						ctx.stroke.miterLimit = miterLimit;
						ctx.stroke.scaleMode = scaleMode;
					}

				case LINE_BITMAP_STYLE:
					var c = data.readLineBitmapStyle();
					if (!maskRender)
					{
						ctx.stroke.fill.identity();
						ctx.stroke.fill.bitmap = c.bitmap;
						ctx.stroke.fill.matrix = c.matrix;
						ctx.stroke.fill.bitmapSmooth = c.smooth;
						ctx.stroke.fill.bitmapRepeat = c.repeat;
					}

				case LINE_GRADIENT_STYLE:
					var c = data.readLineGradientStyle();
					if (!maskRender)
					{
						ctx.stroke.fill.identity();
						ctx.stroke.fill.gradient = Gradient.__pool.get();
						ctx.stroke.fill.gradient.setTo(c.colors, c.alphas, c.ratios, null, c.type, c.interpolationMethod, c.spreadMethod, c.focalPointRatio);
						ctx.stroke.fill.matrix = c.matrix;
					}

				case DRAW_QUADS:
					ctx.build();
					var c = data.readDrawQuads();
					var rects = c.rects;
					var rectIndices = c.indices;
					var rectTransforms = c.transforms;

					ctx.drawQuads(rects, rectIndices, rectTransforms);

				case DRAW_TRIANGLES:
					ctx.build();
					var c = data.readDrawTriangles();

					var vertices = c.vertices;
					var indices = c.indices;
					var uvtData = c.uvtData;
					var culling = c.culling;

					ctx.drawTriangles(vertices, indices, uvtData, culling);

				case DRAW_CIRCLE:
					var c = data.readDrawCircle();

					var x = c.x;
					var y = c.y;
					var r = c.radius;

					ctx.drawCircle(x, y, r);

				case DRAW_ELLIPSE:
					var c = data.readDrawEllipse();
					var x = c.x;
					var y = c.y;
					var width = c.width;
					var height = c.height;

					ctx.drawEllipse(x, y, width, height);

				case DRAW_ROUND_RECT:
					var c = data.readDrawRoundRect();
					var x = c.x;
					var y = c.y;
					var width = c.width;
					var height = c.height;
					var ellipseWidth = c.ellipseWidth;
					var ellipseHeight = c.ellipseHeight;

					if (ellipseHeight == null) ellipseHeight = ellipseWidth;
					if (ellipseWidth > width) ellipseWidth = width;
					if (ellipseHeight > height) ellipseHeight = height;

					ctx.drawRoundRect(x, y, width, height, ellipseWidth, ellipseHeight);

				case DRAW_RECT:
					var c = data.readDrawRect();
					var x = c.x;
					var y = c.y;
					var width = c.width;
					var height = c.height;

					ctx.drawRect(x, y, width, height);

				case WINDING_EVEN_ODD:
					data.readWindingEvenOdd();
					ctx.windingRule = EVENODD;

				case WINDING_NON_ZERO:
					data.readWindingNonZero();
					ctx.windingRule = NONZERO;

				default:
					data.skip(type);
			}
		}

		DrawCommandReader.__pool.release(data);

		ctx.build();

		ctx.graphics = null;

		return graphics.__buffer;
	}

	public static function render(graphics:Graphics, renderer:OpenGLRenderer):Void
	{
		if (!graphics.__visible || graphics.__commands.length == 0) return;

		if ((graphics.__bitmap != null && !graphics.__dirty) || !graphics.__isHardwareCompatible)
		{
			renderer.__softwareRenderer.__pixelRatio = renderer.__pixelRatio;

			var cacheTransform = renderer.__softwareRenderer.__worldTransform;

			// TODO: Embed high-DPI graphics logic in the software renderer?
			// TODO: Unify the software renderer matrix behavior?
			if (graphics.__owner.__drawableType == TEXT_FIELD #if (openfl_disable_hdpi || openfl_disable_hdpi_graphics) || true #end)
			{
				renderer.__softwareRenderer.__worldTransform = Matrix.__identity;
			}
			else
			{
				renderer.__softwareRenderer.__worldTransform = renderer.__worldTransform;
			}

			#if (js && html5)
			CanvasGraphics.render(graphics, cast renderer.__softwareRenderer);
			#elseif lime_cairo
			CairoGraphics.render(graphics, cast renderer.__softwareRenderer);
			#end

			renderer.__softwareRenderer.__worldTransform = cacheTransform;
		}
		else
		{
			graphics.__bitmap = null;

			#if (openfl_disable_hdpi || openfl_disable_hdpi_graphics)
			var pixelRatio = 1;
			#else
			var pixelRatio = renderer.__pixelRatio;
			#end

			graphics.__update(renderer.__worldTransform, pixelRatio);

			var bounds = graphics.__bounds;
			var width = graphics.__width;
			var height = graphics.__height;

			if (!bounds.isEmpty() && width >= 1 && height >= 1)
			{
				if (graphics.__hardwareDirty)
				{
					buildBuffer(graphics);
					graphics.__hardwareDirty = false;
				}

				graphics.__buffer.render(renderer, maskRender);
			}

			graphics.__dirty = false;
		}
	}

	public static function renderMask(graphics:Graphics, renderer:OpenGLRenderer):Void
	{
		maskRender = true;
		render(graphics, renderer);
		maskRender = false;
	}

	public static function hitTest(graphics:Graphics, px:Float, py:Float):Bool
	{
		if (graphics.__commands.length == 0) return false;

		if (!graphics.__isHardwareCompatible)
		{
			#if (js && html5)
			return CanvasGraphics.hitTest(graphics, px, py);
			#elseif (lime_cffi)
			return CairoGraphics.hitTest(graphics, px, py);
			#end
		}

		if (graphics.__hardwareDirty)
		{
			buildBuffer(graphics);
			graphics.__hardwareDirty = false;
		}

		return graphics.__buffer.hitTest(px, py);
	}
}

@:access(openfl.display._internal.FillContext)
@:access(openfl.geom.Rectangle)
@:access(openfl.geom.Point)
@:access(openfl.geom.Matrix)
@:access(openfl.display.Graphics)
@:access(openfl.display.DisplayObject)
@:access(openfl.display._internal.StrokeContext)
@:access(openfl.display._internal.Context3DGraphics)
@:access(openfl.display._internal.Contour)
@:access(openfl.display.OpenGLRenderer)
private class DrawContext
{
	public var graphics:Graphics;
	public var position:Point = new Point();
	public var fills:Array<FillContext> = [];
	public var strokes:Array<StrokeContext> = [];
	public var fill:FillContext;
	public var stroke:StrokeContext;
	public var windingRule:Context3DWindingRule = EVENODD;
	public var curveTolerance:Float = 0.25;

	public static var current:DrawContext;

	private static var __emptyFloatArray:Array<Float> = [];
	private static var __emptyIntArray:Array<Int> = [];
	private static var __tempVerticesVector:Vector<Float> = new Vector<Float>();
	private static var __tempIndicesVector:Vector<Int> = new Vector<Int>();
	private static var __tempUvtDataVector:Vector<Float> = new Vector<Float>();
	private static var __tempFloatVector:Vector<Float> = new Vector<Float>();
	private static var __tempIntVector:Vector<Int> = new Vector<Int>();

	#if openfl_enable_gl_graphics_cache
	private static var __vertexCache:LRUCache<Array<Float>>;
	private static var __indexCache:LRUCache<Array<Int>>;
	private static var __overlappingCache:LRUCache<Bool>;
	#end

	static private function __init__()
	{
		#if openfl_enable_gl_graphics_cache
		var limit = #if (openfl_gl_graphics_cache_limit && !macro) Std.parseInt(haxe.macro.Compiler.getDefine("openfl_gl_graphics_cache_limit")) #else 1024 #end;
		__vertexCache = new LRUCache<Array<Float>>(limit);
		__indexCache = new LRUCache<Array<Int>>(limit);
		__overlappingCache = new LRUCache<Bool>(limit);
		#end
	}

	public function new() {}

	public function newFill()
	{
		if (fill != null) fill.endContour();
		fill = FillContext.__pool.get();
		fills.push(fill);
	}

	public function newStroke()
	{
		if (stroke != null) stroke.endContour();
		stroke = StrokeContext.__pool.get();
		strokes.push(stroke);
	}

	public function init(graphics:Graphics)
	{
		current = this;

		this.graphics = graphics;

		var curveTolerance = #if (openfl_gl_graphics_curve_tolerance && !macro) Std.parseFloat(haxe.macro.Compiler.getDefine("openfl_gl_graphics_curve_tolerance")) #else 0.25 #end;
		#if openfl_enable_gl_graphics_rebuild_curves_when_scaled
		curveTolerance /= Math.min(graphics.__worldScaleX, graphics.__worldScaleY);
		curveTolerance = Math.max(0.0025, curveTolerance);
		#end
		this.curveTolerance = curveTolerance;

		fill = releaseArray(fills, FillContext.__pool, false);
		stroke = releaseArray(strokes, StrokeContext.__pool, false);
		position.setTo(0, 0);
		windingRule = EVENODD;
	}

	public function clearFill():Void
	{
		if (fill != null)
		{
			fill = releaseArray(fills, FillContext.__pool, false);
		}
	}

	public function clearStroke():Void
	{
		if (stroke != null)
		{
			stroke = releaseArray(strokes, StrokeContext.__pool, false);
		}
	}

	public function clearContours():Void
	{
		if (fill != null)
		{
			fill.clearContours();
		}
		if (stroke != null)
		{
			stroke.clearContours();
		}
	}

	public function endContour():Void
	{
		if (fill != null)
		{
			fill.endContour();
		}
		if (stroke != null)
		{
			stroke.endContour();
		}
	}

	public function build():Void
	{
		if (fill != null && fill.contour != null)
		{
			if (stroke != null && stroke.contour != null)
			{
				if (stroke.contour.hash == fill.contour.hash)
				{
					stroke.contour.close();
				}
			}
		}

		endContour();

		var vertices = __tempFloatVector;
		var indices = __tempIntVector;
		for (fill in fills)
		{
			buildFill(fill, vertices, indices);
			graphics.__buffer.append(vertices, indices, null, fill.fill);
		}

		for (stroke in strokes)
		{
			if (stroke.fill.color == 0 || stroke.thickness == null) continue;
			for (contour in stroke.contours)
			{
				var overlapping = buildStrokeContour(stroke, contour, vertices, indices);
				graphics.__buffer.append(vertices, indices, null, stroke.fill, NONE, contour.points, contour.closed, stroke.thickness, overlapping);
			}
		}

		fill = releaseArray(fills, FillContext.__pool, true);
		stroke = releaseArray(strokes, StrokeContext.__pool, true);

		clearContours();
	}

	inline function buildFill(fill:FillContext, vertices:Vector<Float>, indices:Vector<Int>)
	{
		#if openfl_enable_gl_graphics_cache
		var hash = fill.hash;
		hash += windingRule;
		hash += curveTolerance;
		if (__vertexCache.exists(hash))
		{
			untyped (vertices).__array = __vertexCache.get(hash);
			untyped (indices).__array = __indexCache.get(hash);
			return;
		}
		#end

		var fillTess = new Tesselator();
		for (contour in fill.contours)
		{
			var points = contour.points;
			fillTess.addContour(2, untyped (points).__array);
		}
		var windingRule:WindingRule = switch (windingRule)
		{
			case EVENODD: WindingRule.ODD;
			case NONZERO: WindingRule.NON_ZERO;
		}
		fillTess.tesselate(windingRule, POLYGONS, 3, 2);
		untyped (vertices).__array = fillTess.vertices;
		untyped (indices).__array = fillTess.elements;

		#if openfl_enable_gl_graphics_cache
		__vertexCache.set(hash, fillTess.vertices);
		__indexCache.set(hash, fillTess.elements);
		#end
	}

	inline function buildStrokeContour(stroke:StrokeContext, contour:Contour, vertices:Vector<Float>, indices:Vector<Int>)
	{
		#if openfl_disable_gl_hairlines
		var thickness = Math.max(#if (openfl_gl_hairline_thickness && !macro) Std.parseFloat(haxe.macro.Compiler.getDefine("openfl_gl_hairline_thickness")) #else 1.0 #end,
			stroke.thickness);
		#else
		var thickness = stroke.thickness;
		#end
		if (thickness == 0.0)
		{
			untyped vertices.__array = __emptyFloatArray;
			untyped indices.__array = __emptyIntArray;
			return false;
		}

		#if openfl_enable_gl_graphics_cache
		var hash = contour.hash;
		hash += thickness;
		hash += curveTolerance;
		hash += stroke.joints;
		hash += stroke.caps;
		hash += stroke.miterLimit;
		hash += stroke.scaleMode;
		if (__vertexCache.exists(hash))
		{
			untyped vertices.__array = __vertexCache.get(hash);
			untyped indices.__array = __indexCache.get(hash);
			return __overlappingCache.get(hash);
		}
		#end

		var lineTess = new PolyLineTesselator(curveTolerance);
		lineTess.tesselate(contour.points, contour.closed, thickness, stroke.joints, stroke.caps, stroke.miterLimit,
			stroke.scaleMode); // #if openfl_disable_gl_hairlines Math.max(1.0, thickness) #else thickness #end

		untyped vertices.__array = lineTess.vertices;
		untyped indices.__array = lineTess.indices;
		var selfIntersecting = lineTess.selfIntersecting;

		#if openfl_enable_gl_graphics_cache
		__vertexCache.set(hash, untyped (vertices).__array);
		__indexCache.set(hash, untyped (indices).__array);
		__overlappingCache.set(hash, selfIntersecting);
		#end

		return selfIntersecting;
	}

	function releaseArray<T>(arr:Array<T>, pool:ObjectPool<T>, keepLast:Bool)
	{
		var old = keepLast ? arr.pop() : null;
		for (item in arr)
		{
			pool.release(item);
		}
		ArrayUtil.clear(arr);
		if (old != null)
		{
			arr.push(old);
		}
		return old;
	}

	public inline function moveTo(x:Float, y:Float)
	{
		if (fill != null) fill.newContour(x, y);
		if (stroke != null) stroke.newContour(x, y);
		position.setTo(x, y);
	}

	public inline function lineTo(x:Float, y:Float)
	{
		if (fill != null)
		{
			if (fill.contour == null) fill.newContour(position.x, position.y);
			fill.contour.append(LINE_TO(x, y));
		}
		if (stroke != null)
		{
			if (stroke.contour == null) stroke.newContour(position.x, position.y);
			stroke.contour.append(LINE_TO(x, y));
		}
		position.setTo(x, y);
	}

	public function curveTo(cx:Float, cy:Float, x1:Float, y1:Float)
	{
		if (fill != null)
		{
			if (fill.contour == null) fill.newContour(position.x, position.y);
			fill.contour.append(CURVE_TO(cx, cy, x1, y1));
		}
		if (stroke != null)
		{
			if (stroke.contour == null) stroke.newContour(position.x, position.y);
			stroke.contour.append(CURVE_TO(cx, cy, x1, y1));
		}
		position.setTo(x1, y1);
	}

	public function cubicCurveTo(cx1:Float, cy1:Float, cx2:Float, cy2:Float, x1:Float, y1:Float)
	{
		if (fill != null)
		{
			if (fill.contour == null) fill.newContour(position.x, position.y);
			fill.contour.append(CUBIC_CURVE_TO(cx1, cy1, cx2, cy2, x1, y1));
		}
		if (stroke != null)
		{
			if (stroke.contour == null) stroke.newContour(position.x, position.y);
			stroke.contour.append(CUBIC_CURVE_TO(cx1, cy1, cx2, cy2, x1, y1));
		}
		position.setTo(x1, y1);
	}

	public inline function drawTriangles(vertices:Vector<Float>, indices:Vector<Int>, uvtData:Vector<Float>, culling:TriangleCulling):Void
	{
		graphics.__buffer.append(vertices, indices, uvtData, fill.fill, culling);
	}

	public inline function drawQuads(rects:Vector<Float>, rectIndices:Vector<Int>, rectTransforms:Vector<Float>):Void
	{
		#if cpp
		var rects:Array<Float> = rects == null ? null : untyped (rects).__array;
		var indices:Array<Int> = rectIndices == null ? null : untyped (rectIndices).__array;
		var transforms:Array<Float> = rectTransforms == null ? null : untyped (rectTransforms).__array;
		#end

		if (rects == null) return;
		var hasIndices = (rectIndices != null);
		var transformABCD = false, transformXY = false;

		var vertices = __tempVerticesVector;
		var indices = __tempIndicesVector;
		var uvtData = __tempUvtDataVector;

		var length = hasIndices ? rectIndices.length : Std.int(rects.length / 4);
		if (length == 0) return;

		if (rectTransforms != null)
		{
			if (rectTransforms.length >= length * 6)
			{
				transformABCD = true;
				transformXY = true;
			}
			else if (rectTransforms.length >= length * 4)
			{
				transformABCD = true;
			}
			else if (rectTransforms.length >= length * 2)
			{
				transformXY = true;
			}
		}

		vertices.length = length * 8;
		uvtData.length = length * 8;
		indices.length = length * 6;

		var bitmapWidth:Int;
		var bitmapHeight:Int;
		var tileWidth:Float;
		var tileHeight:Float;
		var uvX:Float;
		var uvY:Float;
		var uvRight:Float;
		var uvBottom:Float;
		var x1:Float;
		var y1:Float;
		var x2:Float;
		var y2:Float;
		var x3:Float;
		var y3:Float;
		var x4:Float;
		var y4:Float;
		var ri:Int;
		var ti:Int;

		bitmapWidth = 1;
		bitmapHeight = 1;
		var bitmap = (fill != null) ? fill.fill.bitmap : null;
		if (bitmap != null)
		{
			#if openfl_power_of_two
			while (bitmapWidth < bitmap.width)
			{
				bitmapWidth <<= 1;
			}
			while (bitmapHeight < bitmap.height)
			{
				bitmapHeight <<= 1;
			}
			#else
			bitmapWidth = bitmap.width;
			bitmapHeight = bitmap.height;
			#end
		}

		var tileRect = Rectangle.__pool.get();
		var tileTransform = Matrix.__pool.get();

		for (i in 0...length)
		{
			ri = (hasIndices ? (rectIndices[i] * 4) : i * 4);
			if (ri < 0) continue;
			tileRect.setTo(rects[ri], rects[ri + 1], rects[ri + 2], rects[ri + 3]);

			tileWidth = tileRect.width;
			tileHeight = tileRect.height;

			if (tileWidth <= 0 || tileHeight <= 0)
			{
				continue;
			}

			if (transformABCD && transformXY)
			{
				// this overrides / ignores tileRect.x & tileRect.y
				ti = i * 6;
				tileTransform.setTo(rectTransforms[ti], rectTransforms[ti + 1], rectTransforms[ti + 2], rectTransforms[ti + 3], rectTransforms[ti + 4],
					rectTransforms[ti + 5]);
			}
			else if (transformABCD)
			{
				ti = i * 4;
				tileTransform.setTo(rectTransforms[ti], rectTransforms[ti + 1], rectTransforms[ti + 2], rectTransforms[ti + 3], tileRect.x, tileRect.y);
			}
			else if (transformXY)
			{
				ti = i * 2;
				tileTransform.tx = rectTransforms[ti];
				tileTransform.ty = rectTransforms[ti + 1];
			}
			else
			{
				tileTransform.tx = tileRect.x;
				tileTransform.ty = tileRect.y;
			}

			uvX = tileRect.x / bitmapWidth;
			uvY = tileRect.y / bitmapHeight;
			uvRight = tileRect.right / bitmapWidth;
			uvBottom = tileRect.bottom / bitmapHeight;

			x1 = tileTransform.__transformX(0, 0);
			y1 = tileTransform.__transformY(0, 0);
			x2 = tileTransform.__transformX(tileWidth, 0);
			y2 = tileTransform.__transformY(tileWidth, 0);
			x3 = tileTransform.__transformX(0, tileHeight);
			y3 = tileTransform.__transformY(0, tileHeight);
			x4 = tileTransform.__transformX(tileWidth, tileHeight);
			y4 = tileTransform.__transformY(tileWidth, tileHeight);

			var vo = i << 3; // vertex offset
			var vi = i << 2; // vertex index
			var ii = i * 6; // index offset

			vertices[vo] = x1;
			vertices[vo + 1] = y1;
			vertices[vo + 2] = x2;
			vertices[vo + 3] = y2;
			vertices[vo + 4] = x3;
			vertices[vo + 5] = y3;
			vertices[vo + 6] = x4;
			vertices[vo + 7] = y4;

			uvtData[vo] = uvX;
			uvtData[vo + 1] = uvY;
			uvtData[vo + 2] = uvRight;
			uvtData[vo + 3] = uvY;
			uvtData[vo + 4] = uvX;
			uvtData[vo + 5] = uvBottom;
			uvtData[vo + 6] = uvRight;
			uvtData[vo + 7] = uvBottom;

			indices[ii] = vi;
			indices[ii + 1] = vi + 1;
			indices[ii + 2] = vi + 3;

			indices[ii + 3] = vi;
			indices[ii + 4] = vi + 3;
			indices[ii + 5] = vi + 2;
		}

		Rectangle.__pool.release(tileRect);
		Matrix.__pool.release(tileTransform);

		graphics.__buffer.append(vertices, indices, uvtData, fill.fill);
	}

	public inline function drawRect(x:Float, y:Float, width:Float, height:Float)
	{
		#if openfl_gl_scale9grid
		if (graphics.__useScale9Grid)
		{
			var scaledLeft = graphics.__getScale9GridPositionX(x);
			var scaledTop = graphics.__getScale9GridPositionY(y);
			var scaledRight = graphics.__getScale9GridPositionX(x + width);
			var scaledBottom = graphics.__getScale9GridPositionY(y + height);

			x = scaledLeft;
			y = scaledTop;
			width = scaledRight - scaledLeft;
			height = scaledBottom - scaledTop;
		}
		#end

		if (width != 0.0 || height != 0.0)
		{
			moveTo(x, y);
			lineTo(x + width, y);
			lineTo(x + width, y + height);
			lineTo(x, y + height);
			lineTo(x, y);
		}
	}

	public inline function drawRoundRect(x:Float, y:Float, width:Float, height:Float, ellipseWidth:Float, ellipseHeight:Float)
	{
		var left = x;
		var top = y;
		var right = x + width;
		var bottom = y + height;

		#if openfl_gl_scale9grid
		if (graphics.__useScale9Grid)
		{
			var scaledLeft = graphics.__getScale9GridPositionX(left);
			var scaledTop = graphics.__getScale9GridPositionY(top);
			var scaledRight = graphics.__getScale9GridPositionX(right);
			var scaledBottom = graphics.__getScale9GridPositionY(bottom);
			var scaledEllipseLeft = graphics.__getScale9GridPositionX(left + ellipseWidth * 0.5) - scaledLeft;
			var scaledEllipseRight = scaledRight - graphics.__getScale9GridPositionX(right - ellipseWidth * 0.5);
			var scaledEllipseTop = graphics.__getScale9GridPositionY(top + ellipseHeight * 0.5) - scaledTop;
			var scaledEllipseBottom = scaledBottom - graphics.__getScale9GridPositionY(bottom - ellipseHeight * 0.5);
			var scaledEllipseWidth = Math.min(Math.min(scaledEllipseLeft, scaledEllipseRight), scaledRight - scaledLeft);
			var scaledEllipseHeight = Math.min(Math.min(scaledEllipseTop, scaledEllipseBottom), scaledBottom - scaledTop);

			left = scaledLeft;
			top = scaledTop;
			right = scaledRight;
			bottom = scaledBottom;
			ellipseWidth = scaledEllipseWidth;
			ellipseHeight = scaledEllipseHeight;
			width = right - left;
			height = bottom - top;
		}
		#end

		if (width != 0 && height != 0)
		{
			var rx = ellipseWidth * 0.5;
			var ry = ellipseHeight * 0.5;
			var ox = rx * Context3DGraphics.KAPPA;
			var oy = ry * Context3DGraphics.KAPPA;
			var x0 = left;
			var x1 = right;
			var y0 = top;
			var y1 = bottom;

			moveTo(x1, y1 - ry);
			cubicCurveTo(x1, y1 - ry + oy, x1 - rx + ox, y1, x1 - rx, y1);
			lineTo(x0 + rx, y1);
			cubicCurveTo(x0 + rx - ox, y1, x0, y1 - ry + oy, x0, y1 - ry);
			lineTo(x0, y0 + ry);
			cubicCurveTo(x0, y0 + ry - oy, x0 + rx - ox, y0, x0 + rx, y0);
			lineTo(x1 - rx, y0);
			cubicCurveTo(x1 - rx + ox, y0, x1, y0 + ry - oy, x1, y0 + ry);
			lineTo(x1, y1 - ry);
		}
	}

	public inline function drawCircle(x:Float, y:Float, r:Float)
	{
		drawEllipse(x - r, y - r, r * 2, r * 2);
	}

	public inline function drawEllipse(x:Float, y:Float, width:Float, height:Float)
	{
		#if openfl_gl_scale9grid
		if (graphics.__useScale9Grid)
		{
			var scaledLeft = graphics.__getScale9GridPositionX(x);
			var scaledTop = graphics.__getScale9GridPositionY(y);
			var scaledRight = graphics.__getScale9GridPositionX(x + width);
			var scaledBottom = graphics.__getScale9GridPositionY(y + height);

			x = scaledLeft;
			y = scaledTop;
			width = scaledRight - scaledLeft;
			height = scaledBottom - scaledTop;
		}
		#end

		if (width != 0.0 || height != 0.0)
		{
			var ox = (width / 2.0) * Context3DGraphics.KAPPA; // control point offset horizontal
			var oy = (height / 2.0) * Context3DGraphics.KAPPA; // control point offset vertical
			var xe = x + width; // x-end
			var ye = y + height; // y-end
			var xm = x + width / 2; // x-middle
			var ym = y + height / 2; // y-middle

			moveTo(xe, ym);
			cubicCurveTo(xe, ym + oy, xm + ox, ye, xm, ye);
			cubicCurveTo(xm - ox, ye, x, ym + oy, x, ym);
			cubicCurveTo(x, ym - oy, xm - ox, y, xm, y);
			cubicCurveTo(xm + ox, y, xe, ym - oy, xe, ym);
		}
	}
}

@:access(openfl.display._internal.Contour)
@:access(openfl.display._internal.Fill)
private class FillContext
{
	public var contours:Array<Contour> = [];
	public var contour:Contour;
	public var fill:Fill = new Fill();
	public var hash(get, never):FastHash;

	static private var __pool:ObjectPool<FillContext> = new ObjectPool<FillContext>(() -> new FillContext(), (c) -> c.identity());

	public function new() {}

	public function identity()
	{
		clearContours();
		fill.identity();
	}

	public function clearContours()
	{
		for (contour in contours)
		{
			Contour.__pool.release(contour);
		}
		ArrayUtil.clear(contours);
		contour = null;
	}

	public function newContour(x:Float, y:Float)
	{
		endContour();
		contour = Contour.__pool.get();
		contour.init(x, y, DrawContext.current.curveTolerance);
	}

	public function endContour()
	{
		if (contour != null)
		{
			contour.end();
			contours.push(contour);
		}
		contour = null;
	}

	inline function get_hash():FastHash
	{
		var hash = new FastHash();
		for (contour in contours)
		{
			hash += contour.hash;
		}
		return hash;
	}
}

private class StrokeContext extends FillContext
{
	public var thickness:Null<Float>;
	public var joints:JointStyle;
	public var caps:CapsStyle;
	public var miterLimit:Float;
	public var scaleMode:LineScaleMode;

	static private var __pool:ObjectPool<StrokeContext> = new ObjectPool<StrokeContext>(() -> new StrokeContext(), (c) -> c.identity());

	override public function identity()
	{
		super.identity();
		thickness = null;
		joints = null;
		caps = null;
		miterLimit = 3;
	}
}

enum Context3DWindingRule
{
	EVENODD;
	NONZERO;
}
#end
