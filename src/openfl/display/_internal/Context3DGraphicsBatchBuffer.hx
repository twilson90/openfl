package openfl.display._internal;

import haxe.Constraints.IMap;
import haxe.io.Bytes;
import lime.math.ARGB;
import openfl.display.Graphics;
import openfl.display.OpenGLRenderer;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DClearMask;
import openfl.display3D.IndexBuffer3D;
import openfl.display3D.VertexBuffer3D;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
import openfl.utils.ArrayUtil;
import openfl.utils.ColorUtil;
import openfl.utils.ObjectPool;
import openfl.utils._internal.ArrayBufferView;
import openfl.utils._internal.Float32Array;
import openfl.utils._internal.UInt32Array;
import openfl.utils._internal.IndexArray;
import lime.utils.ArrayBuffer;

@:access(lime.utils.ArrayBufferView)
@:access(openfl.geom.Rectangle)
@:access(openfl.geom.Matrix)
@:access(openfl.display._internal.Fill)
@:access(openfl.display._internal.Gradient)
@:access(openfl.display._internal.Context3DGraphics)
@:access(openfl.display.Graphics)
@:access(openfl.display.Shader)
@:access(openfl.display.DisplayObject)
@:access(openfl.display3D.Context3D)
@:access(openfl.display3D.IndexBuffer3D)
@:access(openfl.display3D.VertexBuffer3D)
class Context3DGraphicsBatchBuffer
{
	static private inline var EPSILON:Float = 1e-6;
	static private inline var DATA_PER_VERTEX:Int = 6;

	private var __context:Context3D;
	private var __graphics:Graphics;
	private var __dirty:Bool = true;
	private var __wireframeDirty:Bool = true;

	private var __triVertexData:Float32Array;
	private var __triIndexData:IndexArray;
	private var __lineVertexData:Float32Array;
	private var __lineIndexData:IndexArray;
	private var __triVertexPosition:Int;
	private var __triIndexPosition:Int;
	private var __lineVertexPosition:Int;
	private var __lineIndexPosition:Int;

	public var length(default, null):Int = 0;

	public var triVertexBuffer(default, null):VertexBuffer3D;
	public var triIndexBuffer(default, null):IndexBuffer3D;
	public var maskQuadVertexBuffer(default, null):VertexBuffer3D;
	public var maskQuadIndexBuffer(default, null):IndexBuffer3D;
	public var lineVertexBuffer(default, null):VertexBuffer3D;
	public var lineIndexBuffer(default, null):IndexBuffer3D;
	public var wireframeIndexBuffer(default, null):IndexBuffer3D;

	public var numTris(default, null):Vector<Int> = new Vector<Int>();
	public var numTriVertices(default, null):Vector<Int> = new Vector<Int>();
	public var numLines(default, null):Vector<Int> = new Vector<Int>();
	public var numWires(default, null):Vector<Int> = new Vector<Int>();
	public var triCulling(default, null):Vector<TriangleCulling> = new Vector<TriangleCulling>();
	public var fill(default, null):Vector<Fill> = new Vector<Fill>();
	public var bounds(default, null):Vector<Rectangle> = new Vector<Rectangle>();
	public var uv(default, null):Vector<Rectangle> = new Vector<Rectangle>();
	public var lineThickness(default, null):Vector<Float> = new Vector<Float>();
	public var selfIntersecting(default, null):Vector<Bool> = new Vector<Bool>();

	private static var __tempUInt32Buffer:UInt32Array;
	private static var __tempFloat32Buffer:Float32Array;
	private static var __tempArrayBuffer:ArrayBuffer;
	private static var __tempColorTransform = new ColorTransform(1, 1, 1, 1, 0, 0, 0, 0);
	private static var __tempVerticesVector:Vector<Float> = new Vector<Float>();
	private static var __tempIndicesVector:Vector<Int> = new Vector<Int>();
	private static var __tempPointsVector:Vector<Float> = new Vector<Float>();
	private static var __tempUvtDataVector:Vector<Float> = new Vector<Float>();
	private static var __tempScale9VerticesVector:Vector<Float> = new Vector<Float>();
	private static var __wireframeKeyIntMap:Map<Int, Bool> = new Map<Int, Bool>();
	private static var __wireframeKeyStringMap:Map<String, Bool> = new Map<String, Bool>();

	@:noCompletion private static function __init__()
	{
		__tempArrayBuffer = new ArrayBuffer(4);
		__tempUInt32Buffer = new UInt32Array(__tempArrayBuffer);
		__tempFloat32Buffer = new Float32Array(__tempArrayBuffer);
	}

	public function dispose():Void
	{
		__graphics = null;

		if (triVertexBuffer != null)
		{
			triVertexBuffer.dispose();
			triIndexBuffer.dispose();
			triVertexBuffer = null;
			triIndexBuffer = null;
		}
		if (wireframeIndexBuffer != null)
		{
			wireframeIndexBuffer.dispose();
			wireframeIndexBuffer = null;
		}
		if (lineVertexBuffer != null)
		{
			lineVertexBuffer.dispose();
			lineIndexBuffer.dispose();
			lineVertexBuffer = null;
			lineIndexBuffer = null;
		}
		reset();
	}

	public function reset():Void
	{
		length = 0;
		__triVertexPosition = 0;
		__triIndexPosition = 0;
		__lineVertexPosition = 0;
		__lineIndexPosition = 0;

		if (maskQuadIndexBuffer != null)
		{
			maskQuadIndexBuffer.dispose();
			maskQuadVertexBuffer.dispose();
			maskQuadIndexBuffer = null;
			maskQuadVertexBuffer = null;
		}

		for (f in fill)
			Fill.__pool.release(f);
		for (r in bounds)
			Rectangle.__pool.release(r);
		for (r in uv)
			Rectangle.__pool.release(r);

		numTris.length = 0;
		numTriVertices.length = 0;
		numLines.length = 0;
		triCulling.length = 0;
		fill.length = 0;
		bounds.length = 0;
		uv.length = 0;
		lineThickness.length = 0;
		selfIntersecting.length = 0;
		__dirty = true;
	}

	public function new(graphics:Graphics)
	{
		this.__graphics = graphics;
	}

	public function applyScale9Grid(vertices:Vector<Float>, output:Vector<Float>):Vector<Float>
	{
		output.length = vertices.length;
		var minX = __graphics.__boundsExStroke.x;
		var minY = __graphics.__boundsExStroke.y;
		var scaledMinX = __graphics.__getScale9GridPositionX(minX);
		var scaledMinY = __graphics.__getScale9GridPositionY(minY);
		var x:Float, y:Float, scaledX:Float, scaledY:Float;

		var numVertices = Std.int(vertices.length / 2);
		for (i in 0...numVertices)
		{
			var vertOffset = i * 2;
			x = vertices[vertOffset];
			y = vertices[vertOffset + 1];
			scaledX = __graphics.__getScale9GridPositionX(x);
			scaledY = __graphics.__getScale9GridPositionY(y);
			output[vertOffset] = (scaledX - scaledMinX) / __graphics.__owner.__scaleX + minX;
			output[vertOffset + 1] = (scaledY - scaledMinY) / __graphics.__owner.__scaleY + minY;
		}
		return output;
	}

	public function append(vertices:Vector<Float>, indices:Vector<Int>, uvtData:Vector<Float>, fill:Fill, triCulling:TriangleCulling = NONE,
			points:Vector<Float> = null, closed:Bool = false, thickness:Null<Float> = null, selfIntersecting:Bool = false)
	{
		var numVertices = vertices != null ? Std.int(vertices.length / 2) : 0;
		var numPoints = points != null ? Std.int(points.length / 2) : 0;
		if (numVertices == 0 && numPoints == 0) return;

		var xy = numVertices > 0 ? vertices : points;
		if (uvtData == null)
		{
			if (fill.bitmap != null)
			{
				uvtData = __tempUvtDataVector;
				__graphics.__generateUV(xy, fill.bitmap.width, fill.bitmap.height, fill.matrix, uvtData);
			}
			else if (fill.shaderBuffer != null)
			{
				uvtData = __tempUvtDataVector;
				__graphics.__generateUV(xy, 1, 1, fill.matrix, uvtData);
			}
			else if (fill.gradient != null)
			{
				uvtData = __tempUvtDataVector;
				__graphics.__generateUV(xy, 819.2, 819.2, fill.matrix, uvtData);
			}
		}

		#if !openfl_gl_scale9grid
		if (__graphics.__useScale9Grid)
		{
			if (numVertices > 0) vertices = applyScale9Grid(vertices, __tempVerticesVector);
			if (numPoints > 0) points = applyScale9Grid(points, __tempPointsVector);
			xy = numVertices > 0 ? vertices : points;
		}
		#end

		var color = fill.color != null ? fill.color : 0;
		var argb:ARGB = color;
		var a = argb.a;
		var r = argb.r;
		var g = argb.g;
		var b = argb.b;

		var isLine = points != null;
		var numIndices = indices != null ? indices.length : 0;
		var numTris = Std.int(numIndices / 3);
		var numLines = isLine ? closed ? numPoints : numPoints - 1 : 0;

		var hasUVData = (uvtData != null);
		var hasUVTData = (hasUVData && uvtData.length >= (numVertices * 3));
		var uvStride = hasUVTData ? 3 : 2;
		var uvOffset:Int, vertOffset:Int, offset:Int, x:Float, y:Float;
		var u:Float = 0.0, v:Float = 0.0, t:Float = 1.0;

		var bounds = Rectangle.__pool.get();
		calculateBounds(xy, bounds, 2);
		var uv = Rectangle.__pool.get();
		if (hasUVData) calculateBounds(uvtData, uv, uvStride);

		if (numVertices > 0)
		{
			__triVertexData = __resizeVertexBuffer(__triVertexData, __triVertexPosition + (numVertices * DATA_PER_VERTEX));

			for (i in 0...numVertices)
			{
				vertOffset = i * 2;
				uvOffset = i * uvStride;

				x = vertices[vertOffset];
				y = vertices[vertOffset + 1];
				if (hasUVData)
				{
					u = uvtData[uvOffset];
					v = uvtData[uvOffset + 1];
					if (hasUVTData)
					{
						t = uvtData[uvOffset + 2];
						x /= t;
						y /= t;
					}
				}

				offset = __triVertexPosition + (i * DATA_PER_VERTEX);
				__triVertexData[offset] = x;
				__triVertexData[offset + 1] = y;
				__triVertexData[offset + 2] = u;
				__triVertexData[offset + 3] = v;
				__triVertexData[offset + 4] = t;
				__setVertexColor(__triVertexData, offset + 5, a, r, g, b);
			}
		}

		if (numIndices > 0)
		{
			var base = Std.int(__triVertexPosition / DATA_PER_VERTEX);
			__triIndexData = __resizeIndexBuffer(__triIndexData, __triIndexPosition + numIndices, base + numVertices);

			for (i in 0...numIndices)
			{
				__triIndexData[__triIndexPosition + i] = base + indices[i];
			}
		}

		if (isLine)
		{
			var numLineIndices = numLines * 2;
			__lineVertexData = __resizeVertexBuffer(__lineVertexData, __lineVertexPosition + (numPoints * DATA_PER_VERTEX));

			for (i in 0...numPoints)
			{
				offset = __lineVertexPosition + (i * DATA_PER_VERTEX);
				x = points[i * 2];
				y = points[i * 2 + 1];
				if (hasUVData)
				{
					u = uv.x + (x / bounds.x) * uv.width;
					v = uv.y + (y / bounds.y) * uv.height;
				}
				__lineVertexData[offset] = x;
				__lineVertexData[offset + 1] = y;
				__lineVertexData[offset + 2] = u;
				__lineVertexData[offset + 3] = v;
				__lineVertexData[offset + 4] = 1.0;
				__setVertexColor(__lineVertexData, offset + 5, a, r, g, b);
			}

			var base = Std.int(__lineVertexPosition / DATA_PER_VERTEX);
			__lineIndexData = __resizeIndexBuffer(__lineIndexData, __lineIndexPosition + numLineIndices, base + numPoints);
			for (i in 0...numLines)
			{
				offset = __lineIndexPosition + (i * 2);
				__lineIndexData[offset] = base + i;
				__lineIndexData[offset + 1] = base + (i + 1) % numPoints;
			}
			__lineVertexPosition += numPoints * DATA_PER_VERTEX;
			__lineIndexPosition += numLineIndices;
		}

		__triVertexPosition += numVertices * DATA_PER_VERTEX;
		__triIndexPosition += numIndices;

		__dirty = true;

		// merge with previous batch if possible
		var batchable = (selfIntersecting || isLine) ? false : isBatchable(fill, triCulling);
		if (batchable)
		{
			var i = length - 1;
			this.numTris[i] += numTris;
			this.numTriVertices[i] += numVertices;
			this.bounds[i].__expand(bounds.x, bounds.y, bounds.width, bounds.height);
			this.uv[i].__expand(uv.x, uv.y, uv.width, uv.height);
			return;
		}

		var fill2 = Fill.__pool.get();
		fill2.copyFrom(fill);

		this.fill.push(fill2);
		this.numTris.push(numTris);
		this.numTriVertices.push(numVertices);
		this.numLines.push(numLines);
		this.triCulling.push(triCulling);
		this.bounds.push(bounds);
		this.uv.push(uv);
		this.lineThickness.push(thickness);
		this.selfIntersecting.push(selfIntersecting);

		length++;
	}

	static private function calculateBounds(points:Vector<Float>, bounds:Rectangle, stride:Int = 2)
	{
		var numPoints = Std.int(points.length / stride);
		var minX = Math.POSITIVE_INFINITY;
		var minY = Math.POSITIVE_INFINITY;
		var maxX = Math.NEGATIVE_INFINITY;
		var maxY = Math.NEGATIVE_INFINITY;
		for (i in 0...numPoints)
		{
			var x = points[i * stride];
			var y = points[i * stride + 1];

			if (x < minX) minX = x;
			if (x > maxX) maxX = x;
			if (y < minY) minY = y;
			if (y > maxY) maxY = y;
		}
		bounds.setTo(minX, minY, maxX - minX, maxY - minY);
		return bounds;
	}

	private inline function isBatchable(fill:Fill, triCulling:TriangleCulling):Bool
	{
		if (length == 0) return false;

		var oldFill = this.fill[length - 1];
		var oldTriCulling = this.triCulling[length - 1];
		var oldIsStroke = this.numLines[length - 1] > 0;

		if (oldIsStroke) return false;
		if (oldTriCulling != triCulling) return false;
		if (!__isFillBatchable(oldFill, fill)) return false;
		return true;
	}

	public function render(renderer:OpenGLRenderer, mask:Bool)
	{
		var context = renderer.__context3D;
		if (context != __context) __dirty = true;

		__context = context;

		if (__dirty)
		{
			__wireframeDirty = true;

			if (__triIndexPosition > 0) triIndexBuffer = __prepareIndexBuffer(triIndexBuffer, __triIndexData, __triIndexPosition);

			if (__triVertexPosition > 0) triVertexBuffer = __prepareVertexBuffer(triVertexBuffer, __triVertexData, __triVertexPosition);

			if (__lineIndexPosition > 0) lineIndexBuffer = __prepareIndexBuffer(lineIndexBuffer, __lineIndexData, __lineIndexPosition);

			if (__lineVertexPosition > 0) lineVertexBuffer = __prepareVertexBuffer(lineVertexBuffer, __lineVertexData, __lineVertexPosition);
		}

		if (__wireframeDirty)
		{
			if (__triIndexPosition > 0 && __graphics.__wireframe) __prepareWireFrameBuffer();
		}
		__dirty = false;
		__wireframeDirty = false;

		Renderer.render(this, renderer, mask);
	}

	public function debug_print()
	{
		trace("Indices (" + __triIndexData.length + "):", [for (i in 0...__triIndexData.length) __triIndexData[i]]);
		trace("Vertices (" + __triVertexData.length + "):", [for (i in 0...__triVertexData.length) __triVertexData[i]]);
	}

	public function hitTest(px:Float, py:Float)
	{
		var numBatches = length;
		var indexOffset = 0;
		var base:Int, i0:Int, i1:Int, i2:Int;
		var x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float;
		for (i in 0...numBatches)
		{
			var numTris = this.numTris[i];
			var bounds = this.bounds[i];
			if (bounds.contains(px, py))
			{
				for (j in 0...numTris)
				{
					base = indexOffset + (j * 3);
					i0 = __triIndexData[base];
					i1 = __triIndexData[base + 1];
					i2 = __triIndexData[base + 2];
					x0 = __triVertexData[i0 * DATA_PER_VERTEX];
					y0 = __triVertexData[i0 * DATA_PER_VERTEX + 1];
					x1 = __triVertexData[i1 * DATA_PER_VERTEX];
					y1 = __triVertexData[i1 * DATA_PER_VERTEX + 1];
					x2 = __triVertexData[i2 * DATA_PER_VERTEX];
					y2 = __triVertexData[i2 * DATA_PER_VERTEX + 1];
					if (__pointInTriangle(px, py, x0, y0, x1, y1, x2, y2))
					{
						return true;
					}
				}
			}
			indexOffset += numTris * 3;
		}

		return false;
	}

	private inline function __setVertexColor(data:Float32Array, offset:Int, a:Int, r:Int, g:Int, b:Int)
	{
		__tempUInt32Buffer[0] = (a << 24) | (r << 16) | (g << 8) | b;
		data[offset] = __tempFloat32Buffer[0];
	}

	private function __resizeVertexBuffer(buffer:Float32Array, length:Int)
	{
		var newBuffer = buffer;
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
		#end
		return newBuffer;
	}

	private function __resizeIndexBuffer(buffer:IndexArray, length:Int, numVertices:Int)
	{
		var newBuffer = buffer;
		var bytesPerElement = __getBytesPerElement(numVertices);
		#if lime
		if (buffer == null)
		{
			newBuffer = new IndexArray(length, bytesPerElement);
		}
		else
		{
			newBuffer = newBuffer.resize(__nextPow2(length), bytesPerElement);
		}
		#end
		return newBuffer;
	}

	private static inline function __getBytesPerElement(numVertices:Int)
	{
		var maxIndex = numVertices - 1;
		if (maxIndex > 4294967295) throw 'Index array value out of range';
		if (maxIndex > 65535) return 4;
		if (maxIndex > 255) return 2;
		return 1;
	}

	public function __prepareWireFrameBuffer()
	{
		var numTriIndices = __triIndexPosition;
		var numTris = Std.int(numTriIndices / 3);
		var numTriVertices = Std.int(__triVertexPosition / DATA_PER_VERTEX);
		var indexData = new IndexArray(numTris * 6,
			__getBytesPerElement(numTriVertices)); // a lot more than we need but the lowest predictable limit without iterating.
		var useIntKeys = numTriVertices < 65536;
		var wireframeIndex = 0;
		var map:IMap<Dynamic, Bool> = useIntKeys ? __wireframeKeyIntMap : __wireframeKeyStringMap;
		var i0:Int, i1:Int, i2:Int, key1:Dynamic, key2:Dynamic, key3:Dynamic;
		var i:Int = 0;

		this.numWires.length = length;
		for (b in 0...length)
		{
			var numTris = this.numTris[b];
			var numWires = 0;
			for (j in 0...numTris)
			{
				i0 = __triIndexData[i];
				i1 = __triIndexData[i + 1];
				i2 = __triIndexData[i + 2];
				key1 = __getWireFrameIndexKey(i0, i1, useIntKeys);
				key2 = __getWireFrameIndexKey(i1, i2, useIntKeys);
				key3 = __getWireFrameIndexKey(i2, i0, useIntKeys);
				if (!map.exists(key1))
				{
					map.set(key1, true);
					indexData[wireframeIndex] = i0;
					indexData[wireframeIndex + 1] = i1;
					wireframeIndex += 2;
					numWires++;
				}
				if (!map.exists(key2))
				{
					map.set(key2, true);
					indexData[wireframeIndex] = i1;
					indexData[wireframeIndex + 1] = i2;
					wireframeIndex += 2;
					numWires++;
				}
				if (!map.exists(key3))
				{
					map.set(key3, true);
					indexData[wireframeIndex] = i2;
					indexData[wireframeIndex + 1] = i0;
					wireframeIndex += 2;
					numWires++;
				}
				i += 3;
			}
			this.numWires[b] = numWires;
		}

		wireframeIndexBuffer = __prepareIndexBuffer(wireframeIndexBuffer, indexData, wireframeIndex);
		map.clear();
	}

	private function __prepareMaskQuadBuffer()
	{
		var numVertices = length * 4;
		var indexData = new IndexArray(length * 6, __getBytesPerElement(numVertices));
		var vertexData = new Float32Array(numVertices * DATA_PER_VERTEX);
		var vertexOffset = 0;
		var indexOffset = 0;
		var offset = 0;

		for (i in 0...length)
		{
			var bounds = this.bounds[i];
			var uv = this.uv[i];
			var fill = this.fill[i];
			var color = fill.color != null ? fill.color : 0;
			var argb:ARGB = color;
			var a = argb.a;
			var r = argb.r;
			var g = argb.g;
			var b = argb.b;

			vertexData[vertexOffset] = bounds.x;
			vertexData[vertexOffset + 1] = bounds.y;
			vertexData[vertexOffset + 2] = uv.x;
			vertexData[vertexOffset + 3] = uv.y;
			vertexData[vertexOffset + 4] = 1.0;
			__setVertexColor(vertexData, vertexOffset + 5, a, r, g, b);

			vertexOffset += DATA_PER_VERTEX;
			vertexData[vertexOffset] = bounds.right;
			vertexData[vertexOffset + 1] = bounds.y;
			vertexData[vertexOffset + 2] = uv.right;
			vertexData[vertexOffset + 3] = uv.y;
			vertexData[vertexOffset + 4] = 1.0;
			__setVertexColor(vertexData, vertexOffset + 5, a, r, g, b);

			vertexOffset += DATA_PER_VERTEX;
			vertexData[vertexOffset] = bounds.right;
			vertexData[vertexOffset + 1] = bounds.bottom;
			vertexData[vertexOffset + 2] = uv.right;
			vertexData[vertexOffset + 3] = uv.bottom;
			vertexData[vertexOffset + 4] = 1.0;
			__setVertexColor(vertexData, vertexOffset + 5, a, r, g, b);

			vertexOffset += DATA_PER_VERTEX;
			vertexData[vertexOffset] = bounds.x;
			vertexData[vertexOffset + 1] = bounds.bottom;
			vertexData[vertexOffset + 2] = uv.x;
			vertexData[vertexOffset + 3] = uv.bottom;
			vertexData[vertexOffset + 4] = 1.0;
			__setVertexColor(vertexData, vertexOffset + 5, a, r, g, b);

			indexData[indexOffset] = offset;
			indexData[indexOffset + 1] = offset + 3;
			indexData[indexOffset + 2] = offset + 1;

			indexData[indexOffset + 3] = offset + 3;
			indexData[indexOffset + 4] = offset + 2;
			indexData[indexOffset + 5] = offset + 1;

			vertexOffset += DATA_PER_VERTEX;
			indexOffset += 6;
			offset += 4;
		}

		maskQuadIndexBuffer = __prepareIndexBuffer(maskQuadIndexBuffer, indexData, indexData.length);
		maskQuadVertexBuffer = __prepareVertexBuffer(maskQuadVertexBuffer, vertexData, vertexData.length);
	}

	private function __prepareIndexBuffer(buffer:IndexBuffer3D, data:IndexArray, length:Int):IndexBuffer3D
	{
		if (buffer == null || length > buffer.__numIndices)
		{
			if (buffer != null) buffer.dispose();
			buffer = __context.createIndexBuffer(length, DYNAMIC_DRAW);
		}
		var _data = data.data;
		buffer.uploadFromTypedArray(_data, length);
		return buffer;
	}

	private function __prepareVertexBuffer(buffer:VertexBuffer3D, data:Float32Array, length:Int):VertexBuffer3D
	{
		if (buffer == null || length > buffer.__numVertices)
		{
			if (buffer != null) buffer.dispose();
			buffer = __context.createVertexBuffer(Std.int(length / DATA_PER_VERTEX), DATA_PER_VERTEX, DYNAMIC_DRAW);
		}
		buffer.uploadFromTypedArray(data, length);
		return buffer;
	}

	// static methods

	private static inline function __getWireFrameIndexKey(a:Int, b:Int, isInt:Bool):Dynamic
	{
		var min = a < b ? a : b;
		var max = a < b ? b : a;
		return isInt ? (min << 16) | max : min + ":" + max;
	}

	private static inline function __nextPow2(v:Int):Int
	{
		var p:Int = 1;
		while (p < v)
			p <<= 1;
		return p;
	}

	private static inline function __cross(ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float):Float
	{
		return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
	}

	private static inline function __pointInTriangle(px:Float, py:Float, ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float):Bool
	{
		var area = __cross(ax, ay, bx, by, cx, cy);
		if (Math.abs(area) < EPSILON) return false;

		var c1 = __cross(ax, ay, bx, by, px, py);
		var c2 = __cross(bx, by, cx, cy, px, py);
		var c3 = __cross(cx, cy, ax, ay, px, py);
		// return (c1 >= -EPSILON && c2 >= -EPSILON && c3 >= -EPSILON);
		var hasNeg = (c1 < -EPSILON) || (c2 < -EPSILON) || (c3 < -EPSILON);
		var hasPos = (c1 > EPSILON) || (c2 > EPSILON) || (c3 > EPSILON);
		return !(hasNeg && hasPos);
	}

	private static inline function __isFillBatchable(oldFill:Fill, fill:Fill):Bool
	{
		if (oldFill.bitmap != fill.bitmap) return false;
		if (oldFill.bitmapSmooth != fill.bitmapSmooth) return false;
		if (oldFill.bitmapRepeat != fill.bitmapRepeat) return false;
		if (!Gradient.__equals(oldFill.gradient, fill.gradient)) return false;
		if (oldFill.shaderBuffer != fill.shaderBuffer) return false;
		return true;
	}
}

@:access(openfl.display._internal.Context3DGraphicsBatchBuffer)
@:access(openfl.display3D.Context3D)
@:access(openfl.geom.Rectangle)
@:access(openfl.geom.Matrix)
@:access(openfl.display._internal.Fill)
@:access(openfl.display._internal.Gradient)
@:access(openfl.display._internal.Context3DGraphics)
@:access(openfl.display.Graphics)
@:access(openfl.display.Shader)
@:access(openfl.display.DisplayObject)
@:access(openfl.display3D.Context3D)
@:access(openfl.display3D.IndexBuffer3D)
@:access(openfl.display3D.VertexBuffer3D)
class Renderer
{
	private static var context:Context3D;
	private static var renderer:OpenGLRenderer;
	private static var buffer:Context3DGraphicsBatchBuffer;
	private static var graphics:Graphics;

	private static var masking:Bool;
	private static var triIndex:Int;
	private static var maskQuadIndex:Int;
	private static var lineIndex:Int;
	private static var wireIndex:Int;
	private static var stencilBase:Int;
	private static var worldAlpha:Float;
	private static var renderTransform:Matrix = new Matrix();
	// private static var adjustedRenderTransform:Matrix = new Matrix();
	private static var renderMatrixArray:Array<Float> = [];
	// private static var adjustedRenderMatrixArray:Array<Float> = [];
	private static var worldColorTransform:ColorTransform;

	private static var numTris:Int;
	private static var numLines:Int;
	private static var numMaskQuads:Int;
	private static var numWires:Int;
	private static var fill:Fill;
	private static var triCulling:TriangleCulling;
	private static var isMasked:Bool;
	private static var isLine:Bool;

	public static inline function render(buffer:Context3DGraphicsBatchBuffer, renderer:OpenGLRenderer, masking:Bool):Void
	{
		if (buffer.length == 0) return;

		Renderer.renderer = renderer;
		Renderer.buffer = buffer;
		Renderer.masking = masking;
		Renderer.context = buffer.__context;
		Renderer.graphics = buffer.__graphics;

		triIndex = 0;
		maskQuadIndex = 0;
		lineIndex = 0;
		wireIndex = 0;
		stencilBase = renderer.__stencilReference;

		renderTransform.copyFrom(graphics.__owner.__renderTransform);
		renderTransform.translate(graphics.__renderTransform.tx, graphics.__renderTransform.ty);
		renderMatrixArray = renderer.__getMatrix(renderTransform, NEVER);

		worldAlpha = renderer.__getAlpha(graphics.__owner.__worldAlpha);
		worldColorTransform = renderer.__getColorTransform(graphics.__owner.__worldColorTransform);

		var i = 0;
		var oldCulling = context.__state.culling;
		while (i < buffer.length)
		{
			numTris = 0;
			numLines = 0;
			numWires = 0;
			numMaskQuads = 0;
			fill = buffer.fill[i];
			triCulling = buffer.triCulling[i];

			var nextIsLine = calculateIsLine(i);
			var nextIsMasked = !nextIsLine && calculateIsMasked(i);
			var nextFill = buffer.fill[i];
			var nextTriCulling = buffer.triCulling[i];

			while (true)
			{
				numTris += buffer.numTris[i];
				numLines += buffer.numLines[i];
				numWires += buffer.numWires[i];
				numMaskQuads++;
				isLine = nextIsLine;
				isMasked = nextIsMasked;

				if ((i + 1) >= buffer.length) break;

				nextIsLine = calculateIsLine(i + 1);
				nextIsMasked = !nextIsLine && calculateIsMasked(i + 1);
				nextFill = buffer.fill[i + 1];
				nextTriCulling = buffer.triCulling[i + 1];

				if (triCulling != nextTriCulling) break;
				if (!masking)
				{
					if (isMasked != nextIsMasked || nextIsMasked) break;
					if (isLine != nextIsLine) break;
					if (!Context3DGraphicsBatchBuffer.__isFillBatchable(fill, nextFill)) break;
				}

				i++;
			}

			setCulling(triCulling);

			if (isMasked)
			{
				if (buffer.maskQuadIndexBuffer == null) buffer.__prepareMaskQuadBuffer();
			}

			__render();
			renderer.__clearShader();

			triIndex += numTris * 3;
			lineIndex += numLines * 2;
			wireIndex += numWires * 2;
			maskQuadIndex += numMaskQuads * 6;

			i++;
		}
		context.setCulling(oldCulling);
	}

	private static inline function copyArray(a1:Array<Float>, a2:Array<Float>):Void
	{
		for (i in 0...a1.length)
		{
			a2[i] = a1[i];
		}
	}

	private static inline function calculateIsMasked(i:Int):Bool
	{
		#if openfl_disable_gl_line_masked_rendering
		return false;
		#else
		return buffer.selfIntersecting[i] && (buffer.fill[i].hasTransparency || worldAlpha < 1.0) && !graphics.__wireframe;
		#end
	}

	private static inline function calculateIsLine(i:Int):Bool
	{
		#if openfl_disable_gl_hairlines
		return false;
		#elseif openfl_disable_gl_auto_hairlines
		return buffer.numLines[i] > 0 && buffer.lineThickness[i] == 0.0;
		#else
		return buffer.numLines[i] > 0
			&& (buffer.lineThickness[i] * Math.min(graphics.__worldScaleX,
				graphics.__worldScaleY)) < #if (openfl_gl_hairline_thickness && !macro) Std.parseFloat(haxe.macro.Compiler.getDefine("openfl_gl_hairline_thickness")) #else 1.0 #end;
		#end
	}

	private static inline function setCulling(triCulling:TriangleCulling):Void
	{
		var culling:openfl.display3D.Context3DTriangleFace = switch (triCulling)
		{
			case POSITIVE: FRONT;
			case NEGATIVE: BACK;
			case NONE: NONE;
		}
		context.setCulling(culling);
	}

	private static inline function __render():Void
	{
		// var matrix = isLine ? adjustedRenderMatrixArray : renderMatrixArray;
		var matrix = renderMatrixArray;
		if (masking)
		{
			renderer.setShader(renderer.__maskShader);
			renderer.applyMatrix(matrix);
			renderer.updateShader();
			drawElements(renderer.__maskShader);
			return;
		}

		var bitmap = fill.bitmap;
		var bitmapSmooth = fill.bitmapSmooth;
		var bitmapRepeat = fill.bitmapRepeat;
		var gradient = fill.gradient;
		var shaderBuffer = fill.shaderBuffer;

		if (isMasked)
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
			renderer.applyMatrix(matrix);
			renderer.updateShader();

			// draw mask positive
			drawElements(renderer.__maskShader);

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
			renderer.applyMatrix(matrix);
			if (bitmap != null)
			{
				renderer.applyBitmapData(bitmap, bitmapSmooth, bitmapRepeat);
			}
			renderer.applyAlpha(worldAlpha);
			renderer.applyColorTransform(worldColorTransform);
			renderer.__updateShaderBuffer(triIndex);
			// update shader buffer needed when parameters have changed.
			shaderBuffer.update(cast shader);
		}
		else if (bitmap != null)
		{
			renderer.setShader(shader);
			renderer.applyGraphicsFillType(1);
			renderer.applyBitmapData(bitmap, bitmapSmooth, bitmapRepeat);
			renderer.applyMatrix(matrix);
			renderer.applyAlpha(worldAlpha);
			renderer.applyColorTransform(worldColorTransform);
			renderer.updateShader();
		}
		else if (gradient != null)
		{
			renderer.setShader(shader);
			renderer.applyGradient(gradient); // applyGraphicsFillType 2 / 3
			renderer.applyMatrix(matrix);
			renderer.applyAlpha(worldAlpha);
			renderer.applyColorTransform(worldColorTransform);
			renderer.updateShader();
		}
		else
		{
			renderer.setShader(shader);
			renderer.applyGraphicsFillType(0);
			renderer.applyHasVertexColors(true);
			renderer.applyMatrix(matrix);
			renderer.applyAlpha(worldAlpha);
			renderer.applyColorTransform(worldColorTransform);
			renderer.updateShader();
		}

		if (isMasked)
		{
			// draw a quad that encompasses the stroke so we can apply the stencil to it.
			drawElements(shader, true);

			if (renderer.__stencilReference > 1)
			{
				context.setStencilActions(FRONT_AND_BACK, EQUAL, DECREMENT_SATURATE, DECREMENT_SATURATE, KEEP);
				context.setStencilReferenceValue(renderer.__stencilReference, 0xFF, 0xFF);
				context.setColorMask(false, false, false, false);

				// draw mask negative
				drawElements(renderer.__maskShader);
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
			drawElements(shader);
		}
	}

	private static inline function drawElements(shader:Shader, isMaskQuad:Bool = false):Void
	{
		if (isMaskQuad && !masking && buffer.maskQuadVertexBuffer != null)
		{
			setVertexBuffer(shader, buffer.maskQuadVertexBuffer);
			context.drawTriangles(buffer.maskQuadIndexBuffer, maskQuadIndex, numMaskQuads * 2);
			renderer.__incrementGLDrawCalls(graphics.__owner);
		}
		else if (isLine && !masking && buffer.lineVertexBuffer != null)
		{
			setVertexBuffer(shader, buffer.lineVertexBuffer);
			context.drawLines(buffer.lineIndexBuffer, lineIndex, numLines);
			renderer.__incrementGLDrawCalls(graphics.__owner);
		}
		else if (graphics.__wireframe && !masking && buffer.triVertexBuffer != null)
		{
			setVertexBuffer(shader, buffer.triVertexBuffer);
			context.drawLines(buffer.wireframeIndexBuffer, wireIndex, numWires);
			renderer.__incrementGLDrawCalls(graphics.__owner);
		}
		else if (buffer.triVertexBuffer != null)
		{
			setVertexBuffer(shader, buffer.triVertexBuffer);
			context.drawTriangles(buffer.triIndexBuffer, triIndex, numTris);
			renderer.__incrementGLDrawCalls(graphics.__owner);
		}
	}

	private static inline function setVertexBuffer(shader:Shader, vertexBuffer:VertexBuffer3D):Void
	{
		if (shader.__position != null) context.setVertexBufferAt(shader.__position.index, vertexBuffer, 0, FLOAT_2);
		if (shader.__textureCoord != null) context.setVertexBufferAt(shader.__textureCoord.index, vertexBuffer, 2, FLOAT_3);
		if (shader.__vertexColor != null) context.setVertexBufferAt(shader.__vertexColor.index, vertexBuffer, 5, BYTES_4);
	}
}
