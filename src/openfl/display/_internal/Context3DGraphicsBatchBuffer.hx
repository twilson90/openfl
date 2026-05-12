package openfl.display._internal;

import openfl.display3D.Context3D;
import openfl.display3D.IndexBuffer3D;
import openfl.display3D.VertexBuffer3D;
import openfl.display.Graphics;
import openfl.geom.Rectangle;
import openfl.utils.ArrayUtil;
import openfl.utils.ColorUtil;
import openfl.utils.ObjectPool;
import openfl.utils._internal.Float32Array;
import openfl.utils._internal.UInt32Array;
import haxe.io.Bytes;

@:access(openfl.geom.Rectangle)
@:access(openfl.display._internal.Fill)
@:access(openfl.display._internal.Gradient)
@:access(openfl.display._internal.Context3DGraphics)
@:access(openfl.display3D.IndexBuffer3D)
@:access(openfl.display3D.VertexBuffer3D)
@:access(openfl.display.Graphics)
class Context3DGraphicsBatchBuffer
{
	static private inline var EPSILON:Float = 1e-6;

	private var context:Context3D;
	private var graphics:Graphics;
	private var dataPerVertex:Int;

	public var length:Int = 0;

	public var vertexBuffer:VertexBuffer3D;
	public var indexBuffer:IndexBuffer3D;
	public var strokeVertexBuffer:VertexBuffer3D;
	public var strokeIndexBuffer:IndexBuffer3D;
	public var wireframeIndexBuffer:IndexBuffer3D;
	public var indexBufferData:UInt32Array;
	public var vertexBufferData:Float32Array;

	public var vertexIndexPosition:Int;
	public var vertexBufferPosition:Int;
	public var indexBufferPosition:Int;

	public var numIndices:Array<Int> = [];
	public var numVertices:Array<Int> = [];
	public var culling:Array<TriangleCulling> = [];
	public var fill:Array<Fill> = [];
	public var bounds:Array<Rectangle> = [];
	public var uv:Array<Rectangle> = [];
	public var isTransparentStroke:Array<Bool> = [];
	public var numTransparentStrokes:Int = 0;

	public var needsFlush:Bool = true;

	private static var __tempColorUInt32:UInt32Array;
	private static var __tempColorFloat32:Float32Array;

	static function __init__()
	{
		var b = Bytes.alloc(4);
		__tempColorUInt32 = UInt32Array.fromBytes(b);
		__tempColorFloat32 = Float32Array.fromBytes(b);
	}

	public function dispose():Void
	{
		reset();
		graphics = null;
	}

	public function reset():Void
	{
		if (vertexBuffer != null) vertexBuffer.dispose();
		if (indexBuffer != null) indexBuffer.dispose();
		if (strokeVertexBuffer != null) strokeVertexBuffer.dispose();
		if (strokeIndexBuffer != null) strokeIndexBuffer.dispose();
		if (wireframeIndexBuffer != null) wireframeIndexBuffer.dispose();

		length = 0;
		vertexIndexPosition = 0;
		vertexBufferPosition = 0;
		indexBufferPosition = 0;
		numTransparentStrokes = 0;

		for (f in fill)
			Fill.__pool.release(f);
		for (r in bounds)
			Rectangle.__pool.release(r);
		for (r in uv)
			Rectangle.__pool.release(r);

		ArrayUtil.clear(numIndices);
		ArrayUtil.clear(numVertices);
		ArrayUtil.clear(culling);
		ArrayUtil.clear(fill);
		ArrayUtil.clear(bounds);
		ArrayUtil.clear(uv);
		ArrayUtil.clear(isTransparentStroke);
		needsFlush = true;
	}

	public function new(graphics:Graphics, dataPerVertex:Int)
	{
		this.graphics = graphics;
		this.dataPerVertex = dataPerVertex;
	}

	public function append(vertices:Vector<Float>, indices:Vector<Int>, uvtData:Vector<Float>, culling:TriangleCulling, fill:Fill, isStroke:Bool)
	{
		var color = uint32toFloat32(fill.color != null ? fill.color : 0);

		var numIndices = indices.length;
		if (numIndices == 0) return;
		var numVertices = Std.int(vertices.length / 2);
		if (numVertices == 0) return;
		var numTris = Std.int(numIndices / 3);

		var isTransparentStroke = isStroke && fill.hasTransparency;
		var hasUVData = (uvtData != null);
		var hasUVTData = (hasUVData && uvtData.length >= (numVertices * 3));
		var uvStride = hasUVTData ? 3 : 2;
		var uvOffset:Int, vertOffset:Int, offset:Int, x:Float, y:Float, u:Float, v:Float, t:Float;
		var minX = Math.POSITIVE_INFINITY;
		var minY = Math.POSITIVE_INFINITY;
		var maxX = Math.NEGATIVE_INFINITY;
		var maxY = Math.NEGATIVE_INFINITY;
		var minU = Math.POSITIVE_INFINITY;
		var minV = Math.POSITIVE_INFINITY;
		var maxU = Math.NEGATIVE_INFINITY;
		var maxV = Math.NEGATIVE_INFINITY;

		vertexBufferData = resizeVertexBuffer(vertexBufferData, vertexBufferPosition + (numVertices * dataPerVertex));
		for (i in 0...numVertices)
		{
			offset = vertexBufferPosition + (i * dataPerVertex);
			vertOffset = i * 2;
			uvOffset = i * uvStride;

			x = vertices[vertOffset];
			y = vertices[vertOffset + 1];
			u = hasUVData ? uvtData[uvOffset] : 0.0;
			v = hasUVData ? uvtData[uvOffset + 1] : 0.0;
			t = 1.0;

			if (hasUVTData)
			{
				t = uvtData[uvOffset + 2];
				x /= t;
				y /= t;
			}

			vertexBufferData[offset] = x;
			vertexBufferData[offset + 1] = y;
			vertexBufferData[offset + 2] = u;
			vertexBufferData[offset + 3] = v;
			vertexBufferData[offset + 4] = t;
			vertexBufferData[offset + 5] = color;

			if (x < minX) minX = x;
			if (y < minY) minY = y;
			if (x > maxX) maxX = x;
			if (y > maxY) maxY = y;

			if (u < minU) minU = u;
			if (v < minV) minV = v;
			if (u > maxU) maxU = u;
			if (v > maxV) maxV = v;
		}

		var bounds = Rectangle.__pool.get();
		bounds.setTo(minX, minY, maxX - minX, maxY - minY);

		var uv = Rectangle.__pool.get();
		uv.setTo(minU, minV, maxU - minU, maxV - minV);

		indexBufferData = resizeIndexBuffer(indexBufferData, indexBufferPosition + numIndices);
		for (i in 0...numIndices)
		{
			indexBufferData[indexBufferPosition + i] = vertexIndexPosition + indices[i];
		}

		vertexIndexPosition += numVertices;
		vertexBufferPosition += numVertices * dataPerVertex;
		indexBufferPosition += numIndices;

		#if !openfl_disable_gl_batching
		if (isBatchable(culling, fill, isTransparentStroke))
		{
			var i = length - 1;
			this.numIndices[i] += numIndices;
			this.numVertices[i] += numVertices;
			this.bounds[i].__expand(bounds.x, bounds.y, bounds.width, bounds.height);
			this.uv[i].__expand(minU, minV, maxU - minU, maxV - minV);
			return;
		}
		#end

		var fill2 = Fill.__pool.get();
		fill2.copyFrom(fill);
		this.fill.push(fill2);

		this.numIndices.push(numIndices);
		this.numVertices.push(numVertices);
		this.culling.push(culling);
		this.bounds.push(bounds);
		this.uv.push(uv);
		this.isTransparentStroke.push(isTransparentStroke);

		if (isTransparentStroke)
		{
			numTransparentStrokes++;
		}

		length++;
		needsFlush = true;
	}

	public inline function isBatchable(culling:TriangleCulling, fill:Fill, isTransparentStroke:Bool):Bool
	{
		var i = length - 1;
		var lastFill = this.fill[i];
		var lastCulling = this.culling[i];
		if (lastCulling != culling) return false;
		if (lastFill.bitmap != fill.bitmap) return false;
		if (lastFill.bitmapSmooth != fill.bitmapSmooth) return false;
		if (lastFill.bitmapRepeat != fill.bitmapRepeat) return false;
		if (!Gradient.__equals(lastFill.gradient, fill.gradient)) return false;
		if (lastFill.shaderBuffer != fill.shaderBuffer) return false;
		if (isTransparentStroke != this.isTransparentStroke[i]) return false;
		if (isTransparentStroke == this.isTransparentStroke[i] && lastFill.color != fill.color) return false;
		return true;
	}

	private function resizeVertexBuffer(buffer:Float32Array, length:Int)
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

	private function resizeIndexBuffer(buffer:UInt32Array, length:Int)
	{
		var newBuffer = buffer;
		#if lime
		if (buffer == null)
		{
			newBuffer = new UInt32Array(length);
		}
		else if (length > buffer.length)
		{
			newBuffer = new UInt32Array(length * 2);
			newBuffer.set(buffer);
		}
		#end
		return newBuffer;
	}

	public function prepareWireFrameBuffer()
	{
		var numIndices = indexBufferPosition;
		var numTris = Std.int(numIndices / 3);
		var bufferData = new UInt32Array(numTris * 6);
		for (i in 0...numTris)
		{
			var i0 = indexBufferData[i * 3];
			var i1 = indexBufferData[i * 3 + 1];
			var i2 = indexBufferData[i * 3 + 2];
			var offset = i * 6;

			// push 3 edges per triangle
			bufferData[offset] = i0;
			bufferData[offset + 1] = i1;

			bufferData[offset + 2] = i1;
			bufferData[offset + 3] = i2;

			bufferData[offset + 4] = i2;
			bufferData[offset + 5] = i0;
		}

		wireframeIndexBuffer = prepareIndexBuffer(wireframeIndexBuffer, bufferData, bufferData.length);
	}

	private function prepareStrokeBuffer()
	{
		var strokeIndexBufferData = new UInt32Array(numTransparentStrokes * 6);
		var strokeVertexBufferData = new Float32Array(numTransparentStrokes * 4 * dataPerVertex);
		var vertexOffset = 0;
		var indexOffset = 0;
		var vertexIndexOffset = 0;

		for (i in 0...length)
		{
			if (isTransparentStroke[i])
			{
				var bounds = this.bounds[i];
				var uv = this.uv[i];
				var fill = this.fill[i];
				var color = uint32toFloat32(fill.color != null ? fill.color : 0);

				strokeVertexBufferData[vertexOffset] = bounds.x;
				strokeVertexBufferData[vertexOffset + 1] = bounds.y;
				strokeVertexBufferData[vertexOffset + 2] = uv.x;
				strokeVertexBufferData[vertexOffset + 3] = uv.y;
				strokeVertexBufferData[vertexOffset + 4] = 1.0;
				strokeVertexBufferData[vertexOffset + 5] = color;

				vertexOffset += dataPerVertex;
				strokeVertexBufferData[vertexOffset] = bounds.right;
				strokeVertexBufferData[vertexOffset + 1] = bounds.y;
				strokeVertexBufferData[vertexOffset + 2] = uv.right;
				strokeVertexBufferData[vertexOffset + 3] = uv.y;
				strokeVertexBufferData[vertexOffset + 4] = 1.0;
				strokeVertexBufferData[vertexOffset + 5] = color;

				vertexOffset += dataPerVertex;
				strokeVertexBufferData[vertexOffset] = bounds.right;
				strokeVertexBufferData[vertexOffset + 1] = bounds.bottom;
				strokeVertexBufferData[vertexOffset + 2] = uv.right;
				strokeVertexBufferData[vertexOffset + 3] = uv.bottom;
				strokeVertexBufferData[vertexOffset + 4] = 1.0;
				strokeVertexBufferData[vertexOffset + 5] = color;

				vertexOffset += dataPerVertex;
				strokeVertexBufferData[vertexOffset] = bounds.x;
				strokeVertexBufferData[vertexOffset + 1] = bounds.bottom;
				strokeVertexBufferData[vertexOffset + 2] = uv.x;
				strokeVertexBufferData[vertexOffset + 3] = uv.bottom;
				strokeVertexBufferData[vertexOffset + 4] = 1.0;
				strokeVertexBufferData[vertexOffset + 5] = color;

				strokeIndexBufferData[indexOffset] = vertexIndexOffset;
				strokeIndexBufferData[indexOffset + 1] = vertexIndexOffset + 3;
				strokeIndexBufferData[indexOffset + 2] = vertexIndexOffset + 1;

				strokeIndexBufferData[indexOffset + 3] = vertexIndexOffset + 3;
				strokeIndexBufferData[indexOffset + 4] = vertexIndexOffset + 2;
				strokeIndexBufferData[indexOffset + 5] = vertexIndexOffset + 1;

				vertexOffset += dataPerVertex;
				indexOffset += 6;
				vertexIndexOffset += 4;
			}
		}

		strokeIndexBuffer = prepareIndexBuffer(strokeIndexBuffer, strokeIndexBufferData, strokeIndexBufferData.length);
		strokeVertexBuffer = prepareVertexBuffer(strokeVertexBuffer, strokeVertexBufferData, strokeIndexBufferData.length);
	}

	private function prepareIndexBuffer(buffer:IndexBuffer3D, data:UInt32Array, length:Int):IndexBuffer3D
	{
		if (buffer == null || length > buffer.__numIndices)
		{
			if (buffer != null) buffer.dispose();
			buffer = context.createIndexBuffer(length, DYNAMIC_DRAW);
		}
		buffer.uploadFromUInt32Array(data);
		return buffer;
	}

	private function prepareVertexBuffer(buffer:VertexBuffer3D, data:Float32Array, length:Int):VertexBuffer3D
	{
		if (buffer == null || length > buffer.__numVertices)
		{
			if (buffer != null) buffer.dispose();
			buffer = context.createVertexBuffer(length, dataPerVertex, DYNAMIC_DRAW);
		}
		buffer.uploadFromTypedArray(data);
		return buffer;
	}

	public function flush(context:Context3D)
	{
		if (!needsFlush && context == this.context) return;

		this.context = context;

		if (indexBufferPosition > 0) indexBuffer = prepareIndexBuffer(indexBuffer, indexBufferData, indexBufferPosition);

		if (vertexBufferPosition > 0) vertexBuffer = prepareVertexBuffer(vertexBuffer, vertexBufferData, vertexBufferPosition);

		if (numTransparentStrokes > 0) prepareStrokeBuffer();

		if (graphics.__wireframe) prepareWireFrameBuffer();

		needsFlush = false;
	}

	public function hitTest(px:Float, py:Float)
	{
		var numBatches = length;
		var indexOffset = 0;
		for (i in 0...numBatches)
		{
			var numIndices = this.numIndices[i];
			var bounds = this.bounds[i];
			if (bounds.contains(px, py))
			{
				var numTris = Std.int(numIndices / 3);
				for (j in 0...numTris)
				{
					var base = indexOffset + j * 3;
					var i0 = indexBufferData[base];
					var i1 = indexBufferData[base + 1];
					var i2 = indexBufferData[base + 2];
					var x0 = vertexBufferData[i0 * dataPerVertex];
					var y0 = vertexBufferData[i0 * dataPerVertex + 1];
					var x1 = vertexBufferData[i1 * dataPerVertex];
					var y1 = vertexBufferData[i1 * dataPerVertex + 1];
					var x2 = vertexBufferData[i2 * dataPerVertex];
					var y2 = vertexBufferData[i2 * dataPerVertex + 1];
					if (pointInTriangle(px, py, x0, y0, x1, y1, x2, y2))
					{
						return true;
					}
				}
			}

			indexOffset += numIndices;
		}

		return false;
	}

	private static inline function cross(ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float):Float
	{
		return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
	}

	private static inline function pointInTriangle(px:Float, py:Float, ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float):Bool
	{
		var area = cross(ax, ay, bx, by, cx, cy);
		if (Math.abs(area) < EPSILON) return false;

		var c1 = cross(ax, ay, bx, by, px, py);
		var c2 = cross(bx, by, cx, cy, px, py);
		var c3 = cross(cx, cy, ax, ay, px, py);
		// return (c1 >= -EPSILON && c2 >= -EPSILON && c3 >= -EPSILON);
		var hasNeg = (c1 < -EPSILON) || (c2 < -EPSILON) || (c3 < -EPSILON);
		var hasPos = (c1 > EPSILON) || (c2 > EPSILON) || (c3 > EPSILON);
		return !(hasNeg && hasPos);
	}

	private static inline function uint32toFloat32(u:Int):Float
	{
		__tempColorUInt32[0] = u;
		return __tempColorFloat32[0];
	}
}
