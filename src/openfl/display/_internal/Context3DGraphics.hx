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
import openfl.display._internal.geom.Tesselator;
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
import openfl.utils.ObjectPool;
import openfl.utils._internal.Float32Array;
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
@:access(openfl.display._internal.Context3DBatchBuffer)
@:access(openfl.display._internal.Gradient)
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
	private static inline var EPSILON:Float = 1e-6;

	private static var blankBitmapData = new BitmapData(1, 1, true, 0xffffffff);
	private static var maskRender:Bool;
	private static var tempColorTransform = new ColorTransform(1, 1, 1, 1, 0, 0, 0, 0);
	private static var tempVerticesVector:Vector<Float> = new Vector<Float>();
	private static var tempScale9VerticesVector:Vector<Float> = new Vector<Float>();
	private static var tempIndicesVector:Vector<Int> = new Vector<Int>();
	private static var tempUvtVector:Vector<Float> = new Vector<Float>();
	private static var fillTess:Tesselator = new Tesselator();
	private static var lineTess:PolyLineTesselator = new PolyLineTesselator();

	private static var graphics:Graphics;
	private static var buffer:Context3DBatchBuffer;

	private static function buildDrawTrianglesBuffer(vertices:Vector<Float>, indices:Vector<Int> = null, uvtData:Vector<Float> = null, fill:Fill,
			triCulling:TriangleCulling = NONE, isStroke:Bool = false):Void
	{
		var numVertices = Std.int(vertices.length / 2);
		if (numVertices < 3) return;

		if (uvtData == null)
		{
			if (fill.bitmap != null)
			{
				uvtData = tempUvtVector;
				graphics.__generateUV(vertices, fill.bitmap.width, fill.bitmap.height, fill.matrix, uvtData);
			}
			else if (fill.shaderBuffer != null)
			{
				uvtData = tempUvtVector;
				graphics.__generateUV(vertices, 1, 1, fill.matrix, uvtData);
			}
			else if (fill.gradient != null)
			{
				uvtData = tempUvtVector;
				graphics.__generateUV(vertices, 819.2, 819.2, fill.matrix, uvtData);
			}
		}

		if (/* !isStroke &&  */ graphics.__useScale9Grid)
		{
			vertices = applyScale9Grid(vertices);
		}

		if (indices == null)
		{
			indices = tempIndicesVector;
			for (i in 0...numVertices)
			{
				indices[i] = i;
			}
		}

		buffer.append(vertices, indices, uvtData, triCulling, fill, isStroke);
	}

	public static function applyScale9Grid(vertices:Vector<Float>):Vector<Float>
	{
		tempScale9VerticesVector.length = vertices.length;
		var minX = graphics.__boundsExStroke.x;
		var minY = graphics.__boundsExStroke.y;
		var scaledMinX = graphics.__getScale9GridPositionX(minX);
		var scaledMinY = graphics.__getScale9GridPositionY(minY);
		var x:Float, y:Float, scaledX:Float, scaledY:Float;

		var numVertices = Std.int(vertices.length / 2);
		for (i in 0...numVertices)
		{
			var vertOffset = i * 2;
			x = vertices[vertOffset];
			y = vertices[vertOffset + 1];
			scaledX = graphics.__getScale9GridPositionX(x);
			scaledY = graphics.__getScale9GridPositionY(y);
			tempScale9VerticesVector[vertOffset] = (scaledX - scaledMinX) / graphics.__owner.__scaleX + minX;
			tempScale9VerticesVector[vertOffset + 1] = (scaledY - scaledMinY) / graphics.__owner.__scaleY + minY;
		}
		return tempScale9VerticesVector;
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
		var data = DrawCommandReader.__pool.get();
		data.reset(graphics.__commands);

		var ctx = DrawContext.__pool.get();

		if (graphics.__buffer == null)
		{
			graphics.__buffer = Context3DBatchBuffer.__pool.get();
		}

		graphics.__buffer.reset(DATA_PER_VERTEX);

		Context3DGraphics.buffer = graphics.__buffer;

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
						if (ctx.fill.fill.gradient == null) ctx.fill.fill.gradient = Gradient.__pool.get();
						ctx.fill.fill.gradient.setTo(c.colors, c.alphas, c.ratios, null, c.type, c.interpolationMethod, c.spreadMethod, c.focalPointRatio);
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
						ctx.stroke.fill.gradient = Gradient.__pool.get();
						ctx.stroke.fill.gradient.setTo(c.colors, c.alphas, c.ratios, null, c.type, c.interpolationMethod, c.spreadMethod, c.focalPointRatio);
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
	}

	private static function buildDrawContext(ctx:DrawContext):Void
	{
		ctx.preBuild();

		for (fill in ctx.fills)
		{
			for (contour in fill.contours)
			{
				fillTess.addContour(2, contour.points);
			}
			var windingRule:WindingRule = switch (ctx.windingRule)
			{
				case EVENODD: WindingRule.ODD;
				case NONZERO: WindingRule.NON_ZERO;
			}
			fillTess.tesselate(windingRule, POLYGONS);
			buildDrawTrianglesBuffer(fillTess.vertices, fillTess.elements, null, fill.fill);
			fillTess.reset();
		}

		for (stroke in ctx.strokes)
		{
			if (stroke.fill.color == 0 || stroke.thickness == null) continue;
			for (contour in stroke.contours)
			{
				var closed = contour.closed;
				lineTess.curveTolerance = ctx.curveTolerance;
				var points = contour.points;
				lineTess.addPoints(points, contour.curve);
				lineTess.tesselate(closed, stroke.thickness, stroke.joints, stroke.caps, stroke.miterLimit, stroke.scaleMode);
				buildDrawTrianglesBuffer(lineTess.vertices, lineTess.indices, null, stroke.fill, NONE, true);
				lineTess.reset();
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

			if (!bounds.isEmpty() && width >= 1 && height >= 1)
			{
				Context3DGraphics.graphics = graphics;
				Context3DGraphics.buffer = graphics.__buffer;
				var context = renderer.__context3D;

				if (graphics.__hardwareDirty)
				{
					buildBuffer();
					if (buffer.wireframeIndexBuffer != null)
					{
						buffer.wireframeIndexBuffer.dispose();
						buffer.wireframeIndexBuffer = null;
					}
					graphics.__hardwareDirty = false;
				}

				buffer.flush(context);

				if (graphics.__wireframe && buffer.wireframeIndexBuffer == null)
				{
					buffer.prepareWireFrameBuffer();
				}

				var numBatches = buffer.length;

				if (numBatches > 0)
				{
					var indexOffset = 0;
					var strokeIndexOffset = 0;
					var shaderBufferOffset = 0;
					var stencilBase = renderer.__stencilReference;

					var renderTransform = Matrix.__pool.get();
					renderTransform.copyFrom(graphics.__owner.__renderTransform);
					renderTransform.translate(graphics.__renderTransform.tx, graphics.__renderTransform.ty);
					var uMatrix = renderer.__getMatrix(renderTransform, NEVER);

					for (i in 0...numBatches)
					{
						var numIndices = buffer.numIndices[i];
						var numVertices = buffer.numVertices[i];
						var triCulling = buffer.culling[i];
						var fill = buffer.fill[i];
						var isTransparentStroke = buffer.isTransparentStroke[i];

						var bitmap = fill.bitmap;
						var bitmapSmooth = fill.bitmapSmooth;
						var bitmapRepeat = fill.bitmapRepeat;
						var gradient = fill.gradient;
						var shaderBuffer = fill.shaderBuffer;

						if (maskRender)
						{
							renderer.setShader(renderer.__maskShader);
							renderer.applyBitmapData(Context3DMaskShader.opaqueBitmapData, true);
							renderer.applyMatrix(uMatrix);
							renderer.updateShader();

							drawElements(context, renderer.__maskShader, buffer, indexOffset, numIndices, triCulling);
						}
						else
						{
							if (isTransparentStroke)
							{
								if (renderer.__stencilReference == 0)
								{
									context.clear(0, 0, 0, 0, 0, 0, Context3DClearMask.STENCIL);
								}

								context.setColorMask(false, false, false, false);
								context.setStencilReferenceValue(renderer.__stencilReference, 0xFF, 0xFF);
								context.setStencilActions(FRONT_AND_BACK, EQUAL, INCREMENT_SATURATE, KEEP, KEEP);

								renderer.__stencilReference++;

								renderer.setShader(renderer.__maskShader);
								renderer.applyBitmapData(Context3DMaskShader.opaqueBitmapData, true);
								renderer.applyMatrix(uMatrix);
								renderer.updateShader();

								drawElements(context, renderer.__maskShader, buffer, indexOffset, numIndices, triCulling);

								context.setColorMask(true, true, true, true);
								context.setStencilReferenceValue(renderer.__stencilReference, 0xFF, 0);
								context.setStencilActions(FRONT_AND_BACK, EQUAL, KEEP, KEEP, KEEP);
							}

							var shader:Shader = renderer.__defaultGraphicsShader;
							if (shaderBuffer != null)
							{
								shader = renderer.__initShaderBuffer(shaderBuffer);
								renderer.__setShaderBuffer(shaderBuffer);
								renderer.applyGraphicsFillType(4);
								renderer.applyMatrix(uMatrix);
								if (bitmap != null)
								{
									renderer.applyBitmapData(bitmap, bitmapSmooth, bitmapRepeat);
								}
								renderer.applyAlpha(graphics.__owner.__worldAlpha);
								renderer.applyColorTransform(graphics.__owner.__worldColorTransform);
								renderer.__updateShaderBuffer(shaderBufferOffset);
								// needed if any uniform parameters have changed.
								// TODO: check if shaderBuffer is dirty and only update it if so.
								shaderBuffer.update(cast shader);
							}
							else if (bitmap != null)
							{
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
								renderer.setShader(shader);
								renderer.applyGradient(gradient);
								renderer.applyMatrix(uMatrix);
								renderer.applyAlpha(graphics.__owner.__worldAlpha);
								renderer.applyColorTransform(graphics.__owner.__worldColorTransform);
								renderer.updateShader();
							}
							else
							{
								renderer.setShader(shader);
								renderer.applyGraphicsFillType(0);
								renderer.applyMatrix(uMatrix);
								renderer.applyAlpha(graphics.__owner.__worldAlpha);
								renderer.applyColorTransform(graphics.__owner.__worldColorTransform);
								renderer.updateShader();
							}

							// drawElements(context, shader, buffer, indexOffset, numIndices, triCulling);

							if (isTransparentStroke)
							{
								// draw a quad that encompasses the stroke so we can apply the stencil to it.
								drawTransparentStroke(context, shader, buffer, strokeIndexOffset, 6, triCulling);
								strokeIndexOffset += 6;

								if (renderer.__stencilReference > 1)
								{
									context.setStencilActions(FRONT_AND_BACK, EQUAL, DECREMENT_SATURATE, DECREMENT_SATURATE, KEEP);
									context.setStencilReferenceValue(renderer.__stencilReference, 0xFF, 0xFF);
									context.setColorMask(false, false, false, false);

									drawElements(context, renderer.__maskShader, buffer, indexOffset, numIndices, triCulling);
									renderer.__stencilReference--;

									context.setStencilActions(FRONT_AND_BACK, EQUAL, KEEP, KEEP, KEEP);
									context.setStencilReferenceValue(renderer.__stencilReference, 0xFF, 0);
									context.setColorMask(true, true, true, true);
								}
								else
								{
									renderer.__stencilReference = 0;
									context.setStencilActions();
									context.setStencilReferenceValue(0, 0, 0);
								}
							}
							else
							{
								drawElements(context, shader, buffer, indexOffset, numIndices, triCulling);
							}
						}

						renderer.__clearShader();

						// shaderBufferOffset += numIndices;
						shaderBufferOffset += numVertices;
						indexOffset += numIndices;
					}
					Matrix.__pool.release(renderTransform);
				}
			}

			graphics.__dirty = false;
		}
	}

	private static function drawTransparentStroke(context:Context3D, shader:Shader, buffer:Context3DBatchBuffer, indexOffset:Int, numIndices:Int,
			triCulling:TriangleCulling):Void
	{
		if (shader.__position != null) context.setVertexBufferAt(shader.__position.index, buffer.strokeVertexBuffer, 0, FLOAT_2);
		if (shader.__textureCoord != null) context.setVertexBufferAt(shader.__textureCoord.index, buffer.strokeVertexBuffer, 2, FLOAT_3);
		if (shader.__vertexColor != null) context.setVertexBufferAt(shader.__vertexColor.index, buffer.strokeVertexBuffer, 5, BYTES_4);

		switch (triCulling)
		{
			case POSITIVE:
				context.setCulling(FRONT);

			case NEGATIVE:
				context.setCulling(BACK);

			case NONE:
				context.setCulling(NONE);
		}

		context.drawTriangles(buffer.strokeIndexBuffer, indexOffset, Std.int(numIndices / 3));

		#if gl_stats
		Context3DStats.incrementDrawCall(DrawCallContext.STAGE);
		graphics.__glDrawCalls++;
		#end

		switch (triCulling)
		{
			case POSITIVE, NONE:
				context.setCulling(BACK);

			default:
		}
	}

	private static function drawElements(context:Context3D, shader:Shader, buffer:Context3DBatchBuffer, indexOffset:Int, numIndices:Int,
			triCulling:TriangleCulling):Void
	{
		if (shader.__position != null) context.setVertexBufferAt(shader.__position.index, buffer.vertexBuffer, 0, FLOAT_2);
		if (shader.__textureCoord != null) context.setVertexBufferAt(shader.__textureCoord.index, buffer.vertexBuffer, 2, FLOAT_3);
		if (shader.__vertexColor != null) context.setVertexBufferAt(shader.__vertexColor.index, buffer.vertexBuffer, 5, BYTES_4);

		switch (triCulling)
		{
			case POSITIVE:
				context.setCulling(FRONT);

			case NEGATIVE:
				context.setCulling(BACK);

			case NONE:
				context.setCulling(NONE);
		}

		if (graphics.__wireframe)
		{
			context.drawLines(buffer.wireframeIndexBuffer, indexOffset * 2, numIndices);
		}
		else
		{
			context.drawTriangles(buffer.indexBuffer, indexOffset, Std.int(numIndices / 3));
		}

		#if gl_stats
		Context3DStats.incrementDrawCall(DrawCallContext.STAGE);
		graphics.__glDrawCalls++;
		#end

		switch (triCulling)
		{
			case POSITIVE, NONE:
				context.setCulling(BACK);

			default:
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

		Context3DGraphics.graphics = graphics;

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

			return graphics.__buffer.hitTest(px, py);
		}
		return false;
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
					stroke.contour.append(fill.contour.points[0], fill.contour.points[1]);
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
			fill.newContour(x, y);
		}
		if (hasStroke)
		{
			stroke.newContour(x, y);
		}
		position.setTo(x, y);
	}

	public inline function appendContour(x:Float, y:Float, isCurve:Bool = false)
	{
		if (hasFill)
		{
			if (fill.contour == null)
			{
				fill.newContour(position.x, position.y);
			}
			fill.contour.append(x, y, isCurve);
		}
		if (hasStroke)
		{
			if (stroke.contour == null)
			{
				stroke.newContour(position.x, position.y);
			}
			stroke.contour.append(x, y, isCurve);
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
			appendContour(x1, y1, true);
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
			appendContour(x1, y1, true);
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
		contour = null;
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

	public function endContour()
	{
		if (contour != null)
		{
			contour.end();
			if (contour.points.length >= 4)
			{
				contours.push(contour);
			}
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
	public var points:Vector<Float> = new Vector<Float>();
	public var curve:Vector<Bool> = new Vector<Bool>();
	public var closed:Bool = false;
	public var x:Float = 0;
	public var y:Float = 0;

	private static var __pool:ObjectPool<Contour> = new ObjectPool<Contour>(() -> new Contour(), (c) -> c.reset());

	public function new()
	{
		reset();
	}

	public inline function reset()
	{
		points.length = 0;
		curve.length = 0;
		closed = false;
		x = 0;
		y = 0;
	}

	public inline function append(x:Float, y:Float, isCurve:Bool = false)
	{
		if (points.length >= 2 && this.x == x && this.y == y) return;
		points.push(x);
		points.push(y);
		curve.push(isCurve);
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
			points.length -= 2;
			curve.length -= 1;
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
