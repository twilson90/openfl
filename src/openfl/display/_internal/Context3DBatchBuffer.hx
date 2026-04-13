package openfl.display._internal;

import openfl.display3D.Context3D;
import openfl.display3D.IndexBuffer3D;
import openfl.display3D.VertexBuffer3D;
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
class Context3DBatchBuffer
{
	static private inline var EPSILON:Float = 1e-6;

	private var context:Context3D;
	private var dataPerVertex:Int;

	public var length:Int = 0;

	public var vertexBuffer:VertexBuffer3D;
	public var indexBuffer:IndexBuffer3D;
	public var strokeVertexBuffer:VertexBuffer3D;
	public var strokeIndexBuffer:IndexBuffer3D;
	public var wireframeIndexBuffer:IndexBuffer3D;
	public var indexBufferData:UInt32Array;
	public var vertexBufferData:Float32Array;
	public var strokeIndexBufferData:UInt32Array;
	public var strokeVertexBufferData:Float32Array;

	public var vertexIndexPosition:Int;
	public var vertexBufferPosition:Int;
	public var indexBufferPosition:Int;
	public var strokeVertexBufferPosition:Int;
	public var strokeVertexIndexPosition:Int;
	public var strokeIndexBufferPosition:Int;

	public var numIndices:Array<Int> = [];
	public var numVertices:Array<Int> = [];
	public var culling:Array<TriangleCulling> = [];
	public var fill:Array<Fill> = [];
	public var bounds:Array<Rectangle> = [];
	public var isTransparentStroke:Array<Bool> = [];

	public var needsFlush:Bool = true;

	private static var __tempColorUInt32:UInt32Array;
	private static var __tempColorFloat32:Float32Array;
	private static var __pool:ObjectPool<Context3DBatchBuffer> = new ObjectPool<Context3DBatchBuffer>(() -> new Context3DBatchBuffer(), (b) -> b.reset());

	static function __init__()
	{
		var b = Bytes.alloc(4);
		__tempColorUInt32 = UInt32Array.fromBytes(b);
		__tempColorFloat32 = Float32Array.fromBytes(b);
	}

	public function new() {}

	public function reset(dataPerVertex:Int = 0)
	{
		this.dataPerVertex = dataPerVertex;
		length = 0;

		vertexIndexPosition = 0;
		vertexBufferPosition = 0;
		indexBufferPosition = 0;
		strokeVertexIndexPosition = 0;
		strokeVertexBufferPosition = 0;
		strokeIndexBufferPosition = 0;

		ArrayUtil.clear(numIndices);
		ArrayUtil.clear(numVertices);
		ArrayUtil.clear(culling);
		for (f in fill)
		{
			Fill.__pool.release(f);
		}
		ArrayUtil.clear(fill);
		for (b in bounds)
		{
			Rectangle.__pool.release(b);
		}
		ArrayUtil.clear(bounds);
		ArrayUtil.clear(isTransparentStroke);
		needsFlush = true;
	}

	public function append(vertices:Vector<Float>, indices:Vector<Int>, uvtData:Vector<Float>, culling:TriangleCulling, fill:Fill, isStroke:Bool)
	{
		var isTransparentStroke = fill.hasTransparency && isStroke;
		var minX = Math.POSITIVE_INFINITY;
		var minY = Math.POSITIVE_INFINITY;
		var maxX = Math.NEGATIVE_INFINITY;
		var maxY = Math.NEGATIVE_INFINITY;
		var color = uint32toFloat32(fill.color != null ? fill.color : 0);

		var numIndices = indices.length;
		var numVertices = Std.int(vertices.length / 2);
		var numTris = Std.int(numIndices / 3);

		if (numIndices == 0) return;

		var hasUVData = (uvtData != null);
		var hasUVTData = (hasUVData && uvtData.length >= (numVertices * 3));
		var uvStride = hasUVTData ? 3 : 2;
		var uvOffset:Int, vertOffset:Int, offset:Int, x:Float, y:Float, u:Float, v:Float, t:Float;

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
		}

		var bounds = Rectangle.__pool.get();
		bounds.setTo(minX, minY, maxX - minX, maxY - minY);

		indexBufferData = resizeIndexBuffer(indexBufferData, indexBufferPosition + numIndices);
		for (i in 0...numIndices)
		{
			indexBufferData[indexBufferPosition + i] = vertexIndexPosition + indices[i];
		}

		if (isTransparentStroke)
		{
			strokeVertexBufferData = resizeVertexBuffer(strokeVertexBufferData, strokeVertexBufferPosition + (dataPerVertex * 4));

			var minU = Math.POSITIVE_INFINITY;
			var minV = Math.POSITIVE_INFINITY;
			var maxU = Math.NEGATIVE_INFINITY;
			var maxV = Math.NEGATIVE_INFINITY;

			// TODO: we could use fill.matrix here
			for (i in 0...numVertices)
			{
				offset = vertexBufferPosition + (i * dataPerVertex);
				var u = vertexBufferData[offset + 2];
				var v = vertexBufferData[offset + 3];

				if (u < minU) minU = u;
				if (v < minV) minV = v;
				if (u > maxU) maxU = u;
				if (v > maxV) maxV = v;
			}

			offset = strokeVertexBufferPosition;

			strokeVertexBufferData[offset] = minX;
			strokeVertexBufferData[offset + 1] = minY;
			strokeVertexBufferData[offset + 2] = minU;
			strokeVertexBufferData[offset + 3] = minV;
			strokeVertexBufferData[offset + 4] = 1.0;
			strokeVertexBufferData[offset + 5] = color;

			offset += dataPerVertex;
			strokeVertexBufferData[offset] = maxX;
			strokeVertexBufferData[offset + 1] = minY;
			strokeVertexBufferData[offset + 2] = maxU;
			strokeVertexBufferData[offset + 3] = minV;
			strokeVertexBufferData[offset + 4] = 1.0;
			strokeVertexBufferData[offset + 5] = color;

			offset += dataPerVertex;
			strokeVertexBufferData[offset] = maxX;
			strokeVertexBufferData[offset + 1] = maxY;
			strokeVertexBufferData[offset + 2] = maxU;
			strokeVertexBufferData[offset + 3] = maxV;
			strokeVertexBufferData[offset + 4] = 1.0;
			strokeVertexBufferData[offset + 5] = color;

			offset += dataPerVertex;
			strokeVertexBufferData[offset] = minX;
			strokeVertexBufferData[offset + 1] = maxY;
			strokeVertexBufferData[offset + 2] = minU;
			strokeVertexBufferData[offset + 3] = maxV;
			strokeVertexBufferData[offset + 4] = 1.0;
			strokeVertexBufferData[offset + 5] = color;

			offset = strokeIndexBufferPosition;
			strokeIndexBufferData = resizeIndexBuffer(strokeIndexBufferData, offset + 6);

			strokeIndexBufferData[offset] = strokeVertexIndexPosition;
			strokeIndexBufferData[offset + 1] = strokeVertexIndexPosition + 3;
			strokeIndexBufferData[offset + 2] = strokeVertexIndexPosition + 1;

			strokeIndexBufferData[offset + 3] = strokeVertexIndexPosition + 3;
			strokeIndexBufferData[offset + 4] = strokeVertexIndexPosition + 2;
			strokeIndexBufferData[offset + 5] = strokeVertexIndexPosition + 1;

			strokeVertexIndexPosition += 4;
			strokeVertexBufferPosition += 4 * dataPerVertex;
			strokeIndexBufferPosition += 6;
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
		this.isTransparentStroke.push(isTransparentStroke);

		length++;
		needsFlush = true;
	}

	public inline function isBatchable(culling:TriangleCulling, fill:Fill, isTransparentStroke:Bool):Bool
	{
		var i = length - 1;
		var lastFill = this.fill[i];
		var lastCulling = this.culling[i];
		if (isTransparentStroke || this.isTransparentStroke[i]) return false;
		if (lastCulling != culling) return false;
		if (lastFill.bitmap != fill.bitmap) return false;
		if (lastFill.bitmapSmooth != fill.bitmapSmooth) return false;
		if (lastFill.bitmapRepeat != fill.bitmapRepeat) return false;
		if (!Gradient.__equals(lastFill.gradient, fill.gradient)) return false;
		if (lastFill.shaderBuffer != fill.shaderBuffer) return false;
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

		if (wireframeIndexBuffer != null)
		{
			wireframeIndexBuffer.dispose();
		}
		wireframeIndexBuffer = context.createIndexBuffer(indexBufferPosition, DYNAMIC_DRAW);
		wireframeIndexBuffer.uploadFromUInt32Array(bufferData);
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

		if (indexBufferPosition > 0)
		{
			indexBuffer = prepareIndexBuffer(indexBuffer, indexBufferData, indexBufferPosition);
		}

		if (vertexBufferPosition > 0)
		{
			vertexBuffer = prepareVertexBuffer(vertexBuffer, vertexBufferData, vertexBufferPosition);
		}

		if (strokeIndexBufferPosition > 0)
		{
			strokeIndexBuffer = prepareIndexBuffer(strokeIndexBuffer, strokeIndexBufferData, strokeIndexBufferPosition);
		}

		if (strokeVertexBufferPosition > 0)
		{
			strokeVertexBuffer = prepareVertexBuffer(strokeVertexBuffer, strokeVertexBufferData, strokeVertexBufferPosition);
		}

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
