package openfl.display._internal;

#if !flash
import haxe.ds.IntMap;
import haxe.ds.StringMap;
import openfl.display.BitmapData;
import openfl.display.CapsStyle;
import openfl.display.Graphics;
import openfl.display.JointStyle;
import openfl.display.LineScaleMode;
import openfl.display.OpenGLRenderer;
import openfl.display._internal.CairoGraphics;
import openfl.display._internal.CanvasGraphics;
import openfl.display._internal.DrawCommandReader;
import openfl.display._internal.geom.Tesselator;
import openfl.display._internal.geom.PolyLineTesselator;
import openfl.display3D.Context3D;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.utils.ArrayUtil;
import openfl.utils.ColorUtil;
import openfl.utils.ObjectPool;
import openfl.utils._internal.Float32Array;
import openfl.utils._internal.UInt16Array;
import openfl.utils._internal.UInt32Array;
#if lime
import lime.math.ARGB;
import lime.utils.ArrayBuffer;
#end
#if gl_stats
import openfl.display._internal.stats.Context3DStats;
import openfl.display._internal.stats.DrawCallContext;
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
@:access(openfl.display._internal.Contour)
@:access(openfl.display._internal.Fill)
@:access(openfl.display._internal.FillContext)
@:access(openfl.display._internal.StrokeContext)
@:access(openfl.display._internal.mesh.Polygon)
@SuppressWarnings("checkstyle:FieldDocComment")
class Context3DGraphics
{
	private static var DATA_PER_VERTEX:Int = 6;
	private static var KAPPA:Float = 0.552284749831; // 4*(√2-1)/3
	public static inline var EPS:Float = 1e-6;

	private static var blankBitmapData = new BitmapData(1, 1, true, 0xffffffff);
	private static var maskRender:Bool;
	private static var tempColorTransform = new ColorTransform(1, 1, 1, 1, 0, 0, 0, 0);
	private static var tempVerticesVector:Vector<Float> = new Vector<Float>();
	private static var tempScale9VerticesVector:Vector<Float> = new Vector<Float>();
	private static var tempIndicesVector:Vector<Int> = new Vector<Int>();
	private static var tempUvtVector:Vector<Float> = new Vector<Float>();

	private static var graphics:Graphics;
	private static var renderer:OpenGLRenderer;
	private static var context:Context3D;

	private static var shaderBuffer:ShaderBuffer;
	private static var shaderBufferOffset:Int;
	private static var vertexIndexPosition:Int;
	private static var vertexBufferPosition:Int;
	private static var indexBufferPosition:Int;

	private static function buildDrawTrianglesBuffer(vertices:Vector<Float>, indices:Vector<Int> = null, uvtData:Vector<Float> = null, fill:Fill,
			triCulling:TriangleCulling = NONE):Void
	{
		var numVertices = Std.int(vertices.length / 2);
		if (numVertices < 3) return;

		if (fill.bitmap != null && uvtData == null)
		{
			uvtData = tempUvtVector;
			graphics.__generateUV(vertices, fill.bitmap.width, fill.bitmap.height, fill.matrix, uvtData);
		}
		if (fill.gradient != null && uvtData == null)
		{
			uvtData = tempUvtVector;
			graphics.__generateUV(vertices, 819.2, 819.2, fill.matrix, uvtData);
		}

		if (indices == null)
		{
			indices = tempIndicesVector;
			for (i in 0...numVertices)
			{
				indices[i] = i;
			}
		}

		var length = indices.length;
		var triCount = Std.int(length / 3);
		var numIndices:Int;

		var hasUVData = (uvtData != null);
		var hasUVTData = (hasUVData && uvtData.length >= (numVertices * 3));
		var uvStride = hasUVTData ? 3 : 2;

		var offset:Int;
		var vertOffset:Int;
		var uvOffset:Int;

		if (graphics.__useScale9Grid)
		{
			tempScale9VerticesVector.length = vertices.length;
			var minX = graphics.__boundsExStroke.x;
			var minY = graphics.__boundsExStroke.y;
			var scaledMinX = graphics.__getScale9GridPositionX(minX);
			var scaledMinY = graphics.__getScale9GridPositionY(minY);
			var x:Float, y:Float, scaledX:Float, scaledY:Float;

			for (i in 0...numVertices)
			{
				vertOffset = i * 2;
				x = vertices[vertOffset];
				y = vertices[vertOffset + 1];
				scaledX = graphics.__getScale9GridPositionX(x);
				scaledY = graphics.__getScale9GridPositionY(y);
				tempScale9VerticesVector[vertOffset] = (scaledX - scaledMinX) / graphics.__owner.scaleX + minX;
				tempScale9VerticesVector[vertOffset + 1] = (scaledY - scaledMinY) / graphics.__owner.scaleY + minY;
			}
			vertices = tempScale9VerticesVector;
		}

		var minX = Math.POSITIVE_INFINITY;
		var minY = Math.POSITIVE_INFINITY;
		var maxX = Math.NEGATIVE_INFINITY;
		var maxY = Math.NEGATIVE_INFINITY;
		var color = ColorUtil.argbToGL(fill.color);

		resizeVertexBuffer(vertexBufferPosition + (numVertices * DATA_PER_VERTEX));
		for (i in 0...numVertices)
		{
			offset = vertexBufferPosition + (i * DATA_PER_VERTEX);
			vertOffset = i * 2;
			uvOffset = i * uvStride;

			var x = vertices[vertOffset];
			var y = vertices[vertOffset + 1];
			var t = 1.0;

			if (hasUVTData)
			{
				t = uvtData[uvOffset + 2];
				x /= t;
				y /= t;
			}

			graphics.__vertexBufferData[offset] = x;
			graphics.__vertexBufferData[offset + 1] = y;
			graphics.__vertexBufferData[offset + 2] = hasUVData ? uvtData[uvOffset] : 0;
			graphics.__vertexBufferData[offset + 3] = hasUVData ? uvtData[uvOffset + 1] : 0;
			graphics.__vertexBufferData[offset + 4] = t;
			graphics.__vertexBufferDataInt[offset + 5] = color;

			if (x < minX) minX = x;
			if (y < minY) minY = y;
			if (x > maxX) maxX = x;
			if (y > maxY) maxY = y;
		}

		var rect = Rectangle.__pool.get();
		rect.setTo(minX, minY, maxX - minX, maxY - minY);

		numIndices = length;
		resizeIndexBuffer(indexBufferPosition + numIndices);
		for (i in 0...length)
		{
			graphics.__indexBufferData[indexBufferPosition + i] = vertexIndexPosition + indices[i];
		}

		vertexIndexPosition += numVertices;
		vertexBufferPosition += numVertices * DATA_PER_VERTEX;
		indexBufferPosition += numIndices;

		graphics.__batchBuffer.append(numIndices, numVertices, triCulling, fill, rect);
		Rectangle.__pool.release(rect);
	}

	public static inline function buildDrawQuadsBuffer(rects:Vector<Float>, indices:Vector<Int>, transforms:Vector<Float>, fill:Fill):Void
	{
		#if cpp
		var rects:Array<Float> = rects == null ? null : untyped (rects).__array;
		var indices:Array<Int> = indices == null ? null : untyped (indices).__array;
		var transforms:Array<Float> = transforms == null ? null : untyped (transforms).__array;
		#end

		if (rects == null) return;
		var hasIndices = (indices != null);
		var transformABCD = false, transformXY = false;

		var length = hasIndices ? indices.length : Std.int(rects.length / 4);
		if (length == 0) return;

		if (transforms != null)
		{
			if (transforms.length >= length * 6)
			{
				transformABCD = true;
				transformXY = true;
			}
			else if (transforms.length >= length * 4)
			{
				transformABCD = true;
			}
			else if (transforms.length >= length * 2)
			{
				transformXY = true;
			}
		}

		tempVerticesVector.length = length * 8;
		tempUvtVector.length = length * 8;
		tempIndicesVector.length = length * 6;

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
		var bitmap = fill.bitmap;
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
			ri = (hasIndices ? (indices[i] * 4) : i * 4);
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
				tileTransform.setTo(transforms[ti], transforms[ti + 1], transforms[ti + 2], transforms[ti + 3], transforms[ti + 4], transforms[ti + 5]);
			}
			else if (transformABCD)
			{
				ti = i * 4;
				tileTransform.setTo(transforms[ti], transforms[ti + 1], transforms[ti + 2], transforms[ti + 3], tileRect.x, tileRect.y);
			}
			else if (transformXY)
			{
				ti = i * 2;
				tileTransform.tx = transforms[ti];
				tileTransform.ty = transforms[ti + 1];
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

			tempVerticesVector[vo] = x1;
			tempVerticesVector[vo + 1] = y1;
			tempVerticesVector[vo + 2] = x2;
			tempVerticesVector[vo + 3] = y2;
			tempVerticesVector[vo + 4] = x3;
			tempVerticesVector[vo + 5] = y3;
			tempVerticesVector[vo + 6] = x4;
			tempVerticesVector[vo + 7] = y4;

			tempUvtVector[vo] = uvX;
			tempUvtVector[vo + 1] = uvY;
			tempUvtVector[vo + 2] = uvRight;
			tempUvtVector[vo + 3] = uvY;
			tempUvtVector[vo + 4] = uvX;
			tempUvtVector[vo + 5] = uvBottom;
			tempUvtVector[vo + 6] = uvRight;
			tempUvtVector[vo + 7] = uvBottom;

			tempIndicesVector[ii] = vi;
			tempIndicesVector[ii + 1] = vi + 1;
			tempIndicesVector[ii + 2] = vi + 3;

			tempIndicesVector[ii + 3] = vi;
			tempIndicesVector[ii + 4] = vi + 3;
			tempIndicesVector[ii + 5] = vi + 2;
		}

		buildDrawTrianglesBuffer(tempVerticesVector, tempIndicesVector, tempUvtVector, fill);

		Rectangle.__pool.release(tileRect);
		Matrix.__pool.release(tileTransform);
	}

	private static inline function buildBuffer():Void
	{
		vertexIndexPosition = 0;
		vertexBufferPosition = 0;
		indexBufferPosition = 0;

		var data = DrawCommandReader.__pool.get();
		data.reset(graphics.__commands);

		var ctx = DrawContext.__pool.get();

		if (graphics.__batchBuffer == null)
		{
			graphics.__batchBuffer = new Context3DBatchBuffer();
		}
		else
		{
			graphics.__batchBuffer.reset();
		}

		var matrix = graphics.__owner.__worldTransform;
		var scaleX = Math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b);
		var scaleY = Math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d);

		for (type in graphics.__commands.types)
		{
			switch (type)
			{
				case MOVE_TO:
					var c = data.readMoveTo();
					var x = c.x;
					var y = c.y;
					ctx.newContour(x, y);

				case LINE_TO:
					var c = data.readLineTo();
					var x = c.x;
					var y = c.y;
					ctx.appendContour(x, y);

				case CURVE_TO:
					var c = data.readCurveTo();
					var x1 = c.controlX;
					var y1 = c.controlY;
					var x2 = c.anchorX;
					var y2 = c.anchorY;
					ctx.appendContourCurve(x1, y1, x2, y2);

				case CUBIC_CURVE_TO:
					var c = data.readCubicCurveTo();
					var x1 = c.controlX1;
					var y1 = c.controlY1;
					var x2 = c.controlX2;
					var y2 = c.controlY2;
					var x3 = c.anchorX;
					var y3 = c.anchorY;
					ctx.appendContourCubicCurve(x1, y1, x2, y2, x3, y3);

				case BEGIN_BITMAP_FILL:
					buildDrawContext(ctx);
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
					buildDrawContext(ctx);
					ctx.newFill();
					var c = data.readBeginGradientFill();
					if (maskRender)
					{
						ctx.fill.fill.color = 0xffffffff;
					}
					else
					{
						ctx.fill.fill.gradient = new Gradient(c.colors, c.alphas, c.ratios, null, c.type, c.interpolationMethod, c.spreadMethod,
							c.focalPointRatio);
						ctx.fill.fill.matrix = c.matrix;
					}

				case BEGIN_FILL:
					buildDrawContext(ctx);
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
					buildDrawContext(ctx);
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
					buildDrawContext(ctx);
					ctx.newFill();

				case LINE_STYLE:
					ctx.newStroke();
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
						ctx.stroke.fill.gradient = new Gradient(c.colors, c.alphas, c.ratios, null, c.type, c.interpolationMethod, c.spreadMethod,
							c.focalPointRatio);
						ctx.stroke.fill.matrix = c.matrix;
					}

				case DRAW_QUADS:
					buildDrawContext(ctx);
					var c = data.readDrawQuads();
					var rects = c.rects;
					var indices = c.indices;
					var transforms = c.transforms;
					buildDrawQuadsBuffer(rects, indices, transforms, ctx.fill.fill);

				case DRAW_TRIANGLES:
					buildDrawContext(ctx);
					var c = data.readDrawTriangles();

					var vertices = c.vertices;
					var indices = c.indices;
					var uvtData = c.uvtData;
					var culling = c.culling;
					buildDrawTrianglesBuffer(vertices, indices, uvtData, ctx.fill.fill, culling);

				case DRAW_CIRCLE:
					var c = data.readDrawCircle();

					var x = c.x;
					var y = c.y;
					var r = c.radius;
					var o = r * KAPPA;
					ctx.newContour(x + r, y);
					ctx.appendContourCubicCurve(x + r, y - o, x + o, y - r, x, y - r);
					ctx.appendContourCubicCurve(x - o, y - r, x - r, y - o, x - r, y);
					ctx.appendContourCubicCurve(x - r, y + o, x - o, y + r, x, y + r);
					ctx.appendContourCubicCurve(x + o, y + r, x + r, y + o, x + r, y);
					ctx.newContour(x + r, y);

				case DRAW_ELLIPSE:
					var c = data.readDrawEllipse();
					var rx = c.width / 2.0;
					var ry = c.height / 2.0;
					var x = c.x + rx;
					var y = c.y + ry;
					var ox = rx * KAPPA;
					var oy = ry * KAPPA;
					ctx.newContour(x + rx, y);
					ctx.appendContourCubicCurve(x + rx, y - oy, x + ox, y - ry, x, y - ry);
					ctx.appendContourCubicCurve(x - ox, y - ry, x - rx, y - oy, x - rx, y);
					ctx.appendContourCubicCurve(x - rx, y + oy, x - ox, y + ry, x, y + ry);
					ctx.appendContourCubicCurve(x + ox, y + ry, x + rx, y + oy, x + rx, y);
					ctx.newContour(x + rx, y);

				case DRAW_ROUND_RECT:
					var c = data.readDrawRoundRect();
					var x = c.x;
					var y = c.y;
					var width = c.width;
					var height = c.height;
					var rx = c.ellipseWidth / 2.0;
					var ry = (c.ellipseHeight != null ? c.ellipseHeight : c.ellipseWidth) / 2.0;
					var ox = rx * KAPPA;
					var oy = ry * KAPPA;
					var right = x + width;
					var bottom = y + height;
					ctx.newContour(x + rx, y);
					ctx.appendContour(right - rx, y);
					ctx.appendContourCubicCurve(right - ox, y, right, y + oy, right, y + ry);
					ctx.appendContour(right, bottom - ry);
					ctx.appendContourCubicCurve(right, bottom - oy, right - ox, bottom, right - rx, bottom);
					ctx.appendContour(x + rx, bottom);
					ctx.appendContourCubicCurve(x + ox, bottom, x, bottom - oy, x, bottom - ry);
					ctx.appendContour(x, y + ry);
					ctx.appendContourCubicCurve(x, y + oy, x + ox, y, x + rx, y);
					ctx.newContour(x + rx, y);

				case DRAW_RECT:
					var c = data.readDrawRect();
					var x = c.x;
					var y = c.y;
					var width = c.width;
					var height = c.height;
					ctx.newContour(x, y);
					ctx.appendContour(x + width, y);
					ctx.appendContour(x + width, y + height);
					ctx.appendContour(x, y + height);
					ctx.appendContour(x, y);
					ctx.newContour(x, y);

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

		buildDrawContext(ctx);
		DrawContext.__pool.release(ctx);

		if (indexBufferPosition > 0)
		{
			var buffer = graphics.__indexBuffer;

			if (buffer == null || indexBufferPosition > graphics.__indexBufferCount)
			{
				if (buffer != null) buffer.dispose();
				buffer = context.createIndexBuffer(indexBufferPosition, DYNAMIC_DRAW);
				graphics.__indexBuffer = buffer;
				graphics.__indexBufferCount = indexBufferPosition;
			}

			buffer.uploadFromTypedArray(graphics.__indexBufferData);
		}

		if (vertexBufferPosition > 0)
		{
			var buffer = graphics.__vertexBuffer;

			if (buffer == null || vertexBufferPosition > graphics.__vertexBufferCount)
			{
				if (buffer != null) buffer.dispose();
				buffer = context.createVertexBuffer(vertexBufferPosition, DATA_PER_VERTEX, DYNAMIC_DRAW);
				graphics.__vertexBuffer = buffer;
				graphics.__vertexBufferCount = vertexBufferPosition;
			}

			buffer.uploadFromTypedArray(graphics.__vertexBufferData);
		}
	}

	public static function buildDrawContext(ctx:DrawContext):Void
	{
		ctx.preBuild();

		if (ctx.hasFill)
		{
			for (fill in ctx.fills)
			{
				var tess = new Tesselator();
				for (contour in fill.contours)
				{
					tess.addContour(2, contour.points);
				}
				var windingRule:WindingRule = switch (ctx.windingRule)
				{
					case EVENODD: WindingRule.ODD;
					case NONZERO: WindingRule.NON_ZERO;
				}
				tess.tesselate(windingRule, POLYGONS);
				buildDrawTrianglesBuffer(tess.vertices, tess.elements, null, fill.fill);
			}
		}

		if (ctx.hasStroke)
		{
			for (stroke in ctx.strokes)
			{
				for (contour in stroke.contours)
				{
					var tess = new PolyLineTesselator(ctx.curveTolerance);
					tess.tesselate(contour.points, contour.closed, stroke.thickness, stroke.joints, stroke.caps, stroke.miterLimit, stroke.scaleMode);
					buildDrawTrianglesBuffer(tess.vertices, tess.indices, null, stroke.fill);
				}
			}
		}

		ctx.postBuild();
	}

	public static function render(graphics:Graphics, renderer:OpenGLRenderer):Void
	{
		if (!graphics.__visible || graphics.__commands.length == 0) return;

		#if gl_stats
		graphics.__glDrawCalls = 0;
		#end

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

			Context3DGraphics.graphics = graphics;
			Context3DGraphics.renderer = renderer;
			context = renderer.__context3D;

			if (!bounds.isEmpty() && width >= 1 && height >= 1)
			{
				if (graphics.__hardwareDirty)
				{
					buildBuffer();
					if (graphics.__wireframeIndexBuffer != null) graphics.__wireframeIndexBuffer.dispose();
					graphics.__wireframeIndexBuffer = null;
					graphics.__hardwareDirty = false;
				}

				if (graphics.__wireframe && graphics.__wireframeIndexBuffer == null)
				{
					var numIndices = indexBufferPosition;
					var triCount = Std.int(numIndices / 3);
					var triBufferData = graphics.__indexBufferData;
					var bufferData = new UInt16Array(triCount * 6);
					for (i in 0...triCount)
					{
						var i0 = triBufferData[i * 3];
						var i1 = triBufferData[i * 3 + 1];
						var i2 = triBufferData[i * 3 + 2];
						var offset = i * 6;

						// push 3 edges per triangle
						bufferData[offset] = i0;
						bufferData[offset + 1] = i1;

						bufferData[offset + 2] = i1;
						bufferData[offset + 3] = i2;

						bufferData[offset + 4] = i2;
						bufferData[offset + 5] = i0;
					}
					graphics.__wireframeIndexBuffer = context.createIndexBuffer(indexBufferPosition, DYNAMIC_DRAW);
					graphics.__wireframeIndexBuffer.uploadFromTypedArray(bufferData);
				}

				var numBatches = graphics.__batchBuffer.length;
				var vertexOffset = 0;
				var indexOffset = 0;
				for (i in 0...numBatches)
				{
					var numIndices = graphics.__batchBuffer.numIndices[i];
					var numVertices = graphics.__batchBuffer.numVertices[i];
					var triCulling = graphics.__batchBuffer.culling[i];
					var fill = graphics.__batchBuffer.fill[i];

					var bitmap = fill.bitmap;
					var bitmapSmooth = fill.bitmapSmooth;
					var bitmapRepeat = fill.bitmapRepeat;
					var gradient = fill.gradient;

					var uMatrix = renderer.__getMatrix(graphics.__owner.__renderTransform, AUTO);
					var shader:Shader;

					if (maskRender)
					{
						shader = renderer.__maskShader;
						renderer.setShader(renderer.__maskShader);
						renderer.applyMatrix(uMatrix);
						// renderer.applyBitmapData(blankBitmapData, false, false);
						renderer.updateShader();
					}
					else if (shaderBuffer != null)
					{
						shader = renderer.__initShaderBuffer(shaderBuffer);
						renderer.__setShaderBuffer(shaderBuffer);
						renderer.applyMatrix(uMatrix);
						renderer.applyBitmapData(bitmap, false, bitmapRepeat);
						renderer.applyAlpha(1);
						renderer.applyColorTransform(null);
						renderer.__updateShaderBuffer(shaderBufferOffset);
					}
					else if (bitmap != null)
					{
						shader = renderer.__defaultGraphicsShader;
						renderer.setShader(shader);
						renderer.applyGraphicsFillType(1);
						renderer.applyMatrix(uMatrix);
						renderer.applyBitmapData(bitmap, bitmapSmooth, bitmapRepeat);
						renderer.applyAlpha(graphics.__owner.__worldAlpha);
						renderer.applyColorTransform(graphics.__owner.__worldColorTransform);
						renderer.updateShader();
					}
					else if (gradient != null)
					{
						shader = renderer.__defaultGraphicsShader;
						renderer.setShader(shader);
						renderer.applyGradient(gradient);
						renderer.applyMatrix(uMatrix);
						renderer.applyAlpha(graphics.__owner.__worldAlpha);
						renderer.applyColorTransform(graphics.__owner.__worldColorTransform);
						renderer.updateShader();
					}
					else
					{
						shader = renderer.__defaultGraphicsShader;
						renderer.setShader(shader);
						renderer.applyGraphicsFillType(0);
						renderer.applyMatrix(uMatrix);
						renderer.applyAlpha(graphics.__owner.__worldAlpha);
						renderer.applyColorTransform(graphics.__owner.__worldColorTransform);
						renderer.updateShader();
					}

					if (shader.__position != null) context.setVertexBufferAt(shader.__position.index, graphics.__vertexBuffer, 0, FLOAT_2);
					if (shader.__textureCoord != null) context.setVertexBufferAt(shader.__textureCoord.index, graphics.__vertexBuffer, 2, FLOAT_3);
					if (shader.__vertexColor != null) context.setVertexBufferAt(shader.__vertexColor.index, graphics.__vertexBuffer, 5, BYTES_4);

					switch (triCulling)
					{
						case POSITIVE:
							context.setCulling(FRONT);

						case NEGATIVE:
							context.setCulling(BACK);

						case NONE:
							context.setCulling(NONE);

						default:
					}

					if (graphics.__wireframe)
					{
						context.drawLines(graphics.__wireframeIndexBuffer, indexOffset, numIndices * 2);
					}
					else
					{
						context.drawTriangles(graphics.__indexBuffer, indexOffset, Std.int(numIndices / 3));
					}

					// This code is here because other draw calls are not aware (currently) of the culling type and just generally expect it to use
					// back face culling by default
					switch (triCulling)
					{
						case POSITIVE, NONE:
							context.setCulling(BACK);

						default:
					}

					#if gl_stats
					Context3DStats.incrementDrawCall(DrawCallContext.STAGE);
					graphics.__glDrawCalls++;
					#end

					renderer.__clearShader();

					shaderBufferOffset += numVertices;
					vertexOffset += numVertices * DATA_PER_VERTEX;
					indexOffset += numIndices;
				}
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

	public static function hitTest(graphics:Graphics, x:Float, y:Float):Bool
	{
		if (graphics.__commands.length == 0) return false;

		Context3DGraphics.graphics = graphics;
		Context3DGraphics.renderer = renderer;
		context = renderer.__context3D;

		var bounds = graphics.__bounds;
		var width = graphics.__width;
		var height = graphics.__height;

		if (!bounds.isEmpty() && width >= 1 && height >= 1)
		{
			if (graphics.__hardwareDirty)
			{
				buildBuffer();
				graphics.__hardwareDirty = false;
			}
		}

		var px = x;
		var py = y;

		// if (graphics.__useScale9Grid)
		// {
		// 	px *= graphics.__owner.scaleX;
		// 	py *= graphics.__owner.scaleY;
		// }

		var vertexBuffer = graphics.__vertexBufferData;
		var indexBuffer = graphics.__indexBufferData;
		var numBatches = graphics.__batchBuffer.length;
		var indexOffset = 0;
		for (i in 0...numBatches)
		{
			var bounds = graphics.__batchBuffer.bounds[i];
			if (!bounds.contains(px, py)) continue;

			var numIndices = graphics.__batchBuffer.numIndices[i];
			var numTris = Std.int(numIndices / 3);
			for (j in 0...numTris)
			{
				var base = indexOffset + j * 3;
				var i0 = indexBuffer[base];
				var i1 = indexBuffer[base + 1];
				var i2 = indexBuffer[base + 2];
				var x0 = vertexBuffer[i0 * DATA_PER_VERTEX];
				var y0 = vertexBuffer[i0 * DATA_PER_VERTEX + 1];
				var x1 = vertexBuffer[i1 * DATA_PER_VERTEX];
				var y1 = vertexBuffer[i1 * DATA_PER_VERTEX + 1];
				var x2 = vertexBuffer[i2 * DATA_PER_VERTEX];
				var y2 = vertexBuffer[i2 * DATA_PER_VERTEX + 1];
				if (pointInTriangle(px, py, x0, y0, x1, y1, x2, y2))
				{
					return true;
				}
			}
			indexOffset += numIndices;
		}

		return false;
	}

	public static inline function cross(ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float):Float
	{
		return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
	}

	public static inline function pointInTriangle(px:Float, py:Float, ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float):Bool
	{
		var c1 = cross(ax, ay, bx, by, px, py);
		var c2 = cross(bx, by, cx, cy, px, py);
		var c3 = cross(cx, cy, ax, ay, px, py);
		return (c1 >= -EPS && c2 >= -EPS && c3 >= -EPS);
	}

	private static function resizeVertexBuffer(length:Int)
	{
		var buffer = graphics.__vertexBufferData;
		var newBuffer:Float32Array;
		#if lime
		if (buffer == null)
		{
			newBuffer = new Float32Array(length);
		}
		else if (length > buffer.length)
		{
			newBuffer = new Float32Array(length * 2);
			newBuffer.set(buffer);
		}
		else
		{
			return;
		}
		graphics.__vertexBufferData = newBuffer;
		graphics.__vertexBufferDataInt = new UInt32Array(newBuffer.buffer);
		#end
	}

	private static function resizeIndexBuffer(length:Int)
	{
		var buffer = graphics.__indexBufferData;
		var newBuffer:UInt16Array;
		#if lime
		if (buffer == null)
		{
			newBuffer = new UInt16Array(length);
		}
		else if (length > buffer.length)
		{
			newBuffer = new UInt16Array(length * 2);
			newBuffer.set(buffer);
		}
		else
		{
			return;
		}
		graphics.__indexBufferData = newBuffer;
		#end
	}

	private static function toScale9Position(pos:Float, scale9Start:Float, scale9Center:Float, unscaledSize:Float, scale:Float):Float
	{
		if (scale <= 0.0)
		{
			// doesn't render if scaled with negative value
			return 0.0;
		}
		var scale9End = unscaledSize - scale9Center - scale9Start;
		var size = unscaledSize * scale;
		var center = size - scale9Start - scale9End;
		if (pos <= scale9Start)
		{
			// start region
			if (center < 0.0)
			{
				return pos * (scale9Start + scale9End + center) / (scale9Start + scale9End);
			}
			return pos;
		}
		if (pos >= (scale9Start + scale9Center))
		{
			// end region
			if (center < 0.0)
			{
				return (scale9Start + (pos - scale9Start - scale9Center)) * (scale9Start + scale9End + center) / (scale9Start + scale9End);
			}
			return scale9Start + center + (pos - scale9Start - scale9Center);
		}
		// center region
		if (center < 0.0)
		{
			return scale9Start * (scale9Start + scale9End + center) / (scale9Start + scale9End);
		}
		return scale9Start + center * (pos - scale9Start) / scale9Center;
	}
}

@:access(openfl.display._internal.Gradient)
class Fill
{
	public var color:Null<Int>;
	public var bitmap:BitmapData;
	public var bitmapSmooth:Bool;
	public var bitmapRepeat:Bool;
	public var matrix:Matrix;
	public var hasFill(get, never):Bool;
	public var gradient:Gradient;

	private static var __pool:ObjectPool<Fill> = new ObjectPool<Fill>(() -> new Fill(), (c) -> c.identity());

	public function new() {}

	public inline function get_hasFill():Bool
	{
		return gradient != null || color != null || bitmap != null;
	}

	public function identity()
	{
		color = 0;
		bitmap = null;
		bitmapSmooth = false;
		bitmapRepeat = false;
		gradient = null;
		matrix = null;
	}

	public function copyFrom(other:Fill)
	{
		color = other.color;
		bitmap = other.bitmap;
		bitmapSmooth = other.bitmapSmooth;
		bitmapRepeat = other.bitmapRepeat;
		gradient = other.gradient;
		matrix = other.matrix;
	}

	public function equals(other:Fill)
	{
		return color == other.color
			&& matrix.equals(other.matrix)
			&& bitmap == other.bitmap
			&& bitmapSmooth == other.bitmapSmooth
			&& bitmapRepeat == other.bitmapRepeat
			&& gradientEquals(gradient, other.gradient);
	}

	public function isBatchable(other:Fill)
	{
		return bitmap == other.bitmap
			&& bitmapSmooth == other.bitmapSmooth
			&& bitmapRepeat == other.bitmapRepeat
			&& gradientEquals(gradient, other.gradient);
	}

	public function gradientEquals(g1:Gradient, g2:Gradient):Bool
	{
		if (g1 == g2) return true;
		if (g1 == null || g2 == null) return false;
		return g1.equals(g2);
	}
}

@:access(openfl.display._internal.FillContext)
@:access(openfl.display._internal.StrokeContext)
@:access(openfl.display._internal.Contour)
class DrawContext
{
	public var position:Point = new Point();
	public var hasFill(get, never):Bool;
	public var hasStroke(get, never):Bool;
	public var fill:FillContext;
	public var stroke:StrokeContext;
	public var fills:Array<FillContext> = [];
	public var strokes:Array<StrokeContext> = [];
	public var curveTolerance:Float = 0.25;
	public var windingRule:Context3DWindingRule = EVENODD;

	private static var __pool:ObjectPool<DrawContext> = new ObjectPool<DrawContext>(() -> new DrawContext(), (c) -> c.identity());

	public function new()
	{
		identity();
	}

	public inline function get_hasFill():Bool
	{
		return fill != null ? fill.fill.hasFill : false;
	}

	public inline function get_hasStroke():Bool
	{
		return stroke != null ? stroke.fill.hasFill : false;
	}

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

	public function identity()
	{
		for (fill in fills)
		{
			FillContext.__pool.release(fill);
		}
		ArrayUtil.clear(fills);
		fill = null;

		for (stroke in strokes)
		{
			StrokeContext.__pool.release(stroke);
		}
		ArrayUtil.clear(strokes);
		stroke = null;

		position.setTo(0, 0);
		windingRule = EVENODD;
	}

	public function preBuild()
	{
		if (hasFill && fill.contour != null)
		{
			if (hasStroke && stroke.contour != null)
			{
				if (strokes.length == fills.length)
				{
					stroke.contour.closed = true;
				}
				else if (stroke.contour != null)
				{
					stroke.appendContour(fill.contour.points[0], fill.contour.points[1]);
				}
			}
			fill.endContour();
		}

		if (hasStroke && stroke.contour != null)
		{
			stroke.endContour();
		}
	}

	public function postBuild()
	{
		var oldFill = fills.pop();
		for (fill in fills)
		{
			FillContext.__pool.release(fill);
		}
		ArrayUtil.clear(fills);
		if (oldFill != null)
		{
			fills.push(oldFill);
			oldFill.clearContours();
			fill = oldFill;
		}

		var oldStroke = strokes.pop();
		for (stroke in strokes)
		{
			StrokeContext.__pool.release(stroke);
		}
		ArrayUtil.clear(strokes);
		if (oldStroke != null)
		{
			strokes.push(oldStroke);
			oldStroke.clearContours();
			stroke = oldStroke;
		}
	}

	public inline function newContour(x:Float, y:Float)
	{
		if (hasFill)
		{
			fill.endContour();
			fill.newContour(x, y);
		}
		if (hasStroke)
		{
			stroke.endContour();
			stroke.newContour(x, y);
		}
		position.setTo(x, y);
	}

	public inline function appendContour(x:Float, y:Float)
	{
		if (hasFill)
		{
			if (fill.contour == null)
			{
				fill.newContour(position.x, position.y);
			}
			fill.appendContour(x, y);
		}
		if (hasStroke)
		{
			if (stroke.contour == null)
			{
				stroke.newContour(position.x, position.y);
			}
			stroke.appendContour(x, y);
		}
		position.setTo(x, y);
	}

	public function appendContourCurve(cx:Float, cy:Float, x1:Float, y1:Float)
	{
		var x0 = position.x;
		var y0 = position.y;
		var dx = x1 - x0;
		var dy = y1 - y0;

		var d = Math.abs((cx - x1) * dy - (cy - y1) * dx);

		if (d * d <= curveTolerance * (dx * dx + dy * dy))
		{
			appendContour(x1, y1);
			return;
		}

		var x01 = (x0 + cx) * 0.5;
		var y01 = (y0 + cy) * 0.5;

		var x12 = (cx + x1) * 0.5;
		var y12 = (cy + y1) * 0.5;

		var xm = (x01 + x12) * 0.5;
		var ym = (y01 + y12) * 0.5;

		appendContourCurve(x01, y01, xm, ym);
		appendContourCurve(x12, y12, x1, y1);
	}

	public function appendContourCubicCurve(cx1:Float, cy1:Float, cx2:Float, cy2:Float, x1:Float, y1:Float)
	{
		var x0 = position.x;
		var y0 = position.y;
		var dx = x1 - x0;
		var dy = y1 - y0;

		var d1 = Math.abs((cx1 - x1) * dy - (cy1 - y1) * dx);
		var d2 = Math.abs((cx2 - x1) * dy - (cy2 - y1) * dx);

		if ((d1 + d2) * (d1 + d2) <= curveTolerance * (dx * dx + dy * dy))
		{
			appendContour(x1, y1);
			return;
		}

		var x01 = (x0 + cx1) * 0.5;
		var y01 = (y0 + cy1) * 0.5;

		var x12 = (cx1 + cx2) * 0.5;
		var y12 = (cy1 + cy2) * 0.5;

		var x23 = (cx2 + x1) * 0.5;
		var y23 = (cy2 + y1) * 0.5;

		var x012 = (x01 + x12) * 0.5;
		var y012 = (y01 + y12) * 0.5;

		var x123 = (x12 + x23) * 0.5;
		var y123 = (y12 + y23) * 0.5;

		var xm = (x012 + x123) * 0.5;
		var ym = (y012 + y123) * 0.5;

		appendContourCubicCurve(x01, y01, x012, y012, xm, ym);
		appendContourCubicCurve(x123, y123, x23, y23, x1, y1);
	}
}

@:access(openfl.display._internal.Contour)
@:access(openfl.display._internal.Fill)
class FillContext
{
	public var contours:Array<Contour> = [];
	public var contour:Contour;
	public var fill:Fill = new Fill();

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
	}

	public function newContour(x:Float, y:Float)
	{
		endContour();
		contour = Contour.__pool.get();
		contour.append(x, y);
	}

	public function appendContour(x:Float, y:Float)
	{
		contour.append(x, y);
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
}

class StrokeContext extends FillContext
{
	public var thickness:Null<Float>;
	public var joints:JointStyle;
	public var caps:CapsStyle;
	public var miterLimit:Float;
	public var scaleMode:LineScaleMode;

	static private var __pool:ObjectPool<StrokeContext> = new ObjectPool<StrokeContext>(() -> new StrokeContext(), (c) -> c.identity());

	public function new()
	{
		super();
	}

	override public function identity()
	{
		super.identity();

		thickness = null;
		joints = null;
		caps = null;
		miterLimit = 3;
	}
}

class Contour
{
	public var points:Array<Float> = [];
	public var closed:Bool;
	public var x:Float = 0;
	public var y:Float = 0;

	private static var __pool:ObjectPool<Contour> = new ObjectPool<Contour>(() -> new Contour(), (c) -> c.free());

	public function new()
	{
		free();
	}

	public inline function free()
	{
		ArrayUtil.clear(points);
		closed = false;
		x = 0;
		y = 0;
	}

	public inline function append(x:Float, y:Float)
	{
		if (points.length >= 2 && this.x == x && this.y == y) return;
		points.push(x);
		points.push(y);
		this.x = x;
		this.y = y;
	}

	public function end()
	{
		if (points.length < 4) return;
		var firstX = points[0];
		var firstY = points[1];
		if (firstX == x && firstY == y)
		{
			ArrayUtil.resize(points, points.length - 2);
			closed = true;
		}
	}
}

enum Context3DWindingRule
{
	EVENODD;
	NONZERO;
}
#end
