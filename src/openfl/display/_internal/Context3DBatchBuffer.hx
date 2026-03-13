package openfl.display._internal;

import openfl.utils.ArrayUtil;
import openfl.geom.Rectangle;
import openfl.display._internal.Context3DGraphics.Fill;

@:access(openfl.geom.Rectangle)
@:access(openfl.display._internal.Fill)
class Context3DBatchBuffer
{
	public var length:Int;

	public var numIndices:Array<Int>;
	public var numVertices:Array<Int>;
	public var culling:Array<TriangleCulling>;
	public var fill:Array<Fill>;
	public var bounds:Array<Rectangle>;

	public function new()
	{
		length = 0;
		numIndices = [];
		numVertices = [];
		culling = [];
		fill = [];
		bounds = [];
	}

	public function reset()
	{
		length = 0;
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
	}

	public function append(numIndices:Int, numVertices:Int, culling:TriangleCulling, _fill:Fill, _bounds:Rectangle)
	{
		if (numIndices == 0) return;

		#if !openfl_disable_gl_batching
		var i = this.numIndices.length - 1;
		if (culling == this.culling[i] && _fill.isBatchable(this.fill[i]))
		{
			this.numIndices[i] += numIndices;
			this.numVertices[i] += numVertices;
			this.bounds[i].__expand(_bounds.x, _bounds.y, _bounds.width, _bounds.height);
			return;
		}
		#end

		this.numIndices.push(numIndices);
		this.numVertices.push(numVertices);
		this.culling.push(culling);
		var fill = Fill.__pool.get();
		fill.copyFrom(_fill);
		this.fill.push(fill);
		var bounds = Rectangle.__pool.get();
		bounds.copyFrom(_bounds);
		this.bounds.push(bounds);
		length++;
	}
}
