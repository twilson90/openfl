package openfl.utils._internal;

import haxe.io.Bytes;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
import openfl.geom.Point;
import openfl.geom.ColorTransform;

abstract FastHash(Int) from Int to Int
{
	private static var __bytes:Bytes;
	static inline var FNV_OFFSET_BASIS:Int = -2128831035;
	static inline var FNV_PRIME:Int = 16777619;

	private static function __init__():Void
	{
		__bytes = Bytes.alloc(8);
	}

	public inline function new()
	{
		this = FNV_OFFSET_BASIS;
	}

	public inline function clear()
	{
		this = FNV_OFFSET_BASIS;
	}

	// Helper: add a single byte
	inline function addByte(b:Int):FastHash
	{
		this = (this ^ (b & 0xFF)) * FNV_PRIME;
		this &= 0xFFFFFFFF;
		return this;
	}

	// Operator overloading: += for strings

	@:op(A += B)
	public inline function addString(s:String):FastHash
	{
		var bytes = Bytes.ofString(s);
		this = __addBytes(bytes, 0, bytes.length);
		return this;
	}

	// Operator overloading: += for integers

	@:op(A += B)
	public inline function addInt(v:Int):FastHash
	{
		var n = v;
		this = addByte(n & 0xFF);
		n >>= 8;
		this = addByte(n & 0xFF);
		n >>= 8;
		this = addByte(n & 0xFF);
		n >>= 8;
		this = addByte(n & 0xFF);
		return this;
	}

	// Operator overloading: += for floats

	@:op(A += B)
	public inline function addFloat(v:Float):FastHash
	{
		__bytes.setDouble(0, v);
		__addBytes(__bytes, 0, 8);
		return this;
	}

	@:op(A += B)
	public inline function addEnum(e:EnumValue):FastHash
	{
		addInt(Type.enumIndex(e));
		return this;
	}

	@:op(A += B)
	public inline function addHash(other:FastHash):FastHash
	{
		addInt(cast other);
		return this;
	}

	@:op(A += B)
	public inline function addIntArray(other:Array<Int>):FastHash
	{
		for (i in other)
			addInt(i);
		return this;
	}

	@:op(A += B)
	public inline function addFloatArray(other:Array<Float>):FastHash
	{
		for (i in other)
			addFloat(i);
		return this;
	}

	@:op(A += B)
	public inline function addMatrix(other:Matrix):FastHash
	{
		addFloat(other.a);
		addFloat(other.b);
		addFloat(other.c);
		addFloat(other.d);
		addFloat(other.tx);
		addFloat(other.ty);
		return this;
	}

	@:op(A += B)
	public inline function addRectangle(other:Rectangle):FastHash
	{
		addFloat(other.x);
		addFloat(other.y);
		addFloat(other.width);
		addFloat(other.height);
		return this;
	}

	@:op(A += B)
	public inline function addPoint(other:Point):FastHash
	{
		addFloat(other.x);
		addFloat(other.y);
		return this;
	}

	@:op(A += B)
	public inline function addColorTransform(other:ColorTransform):FastHash
	{
		addFloat(other.redMultiplier);
		addFloat(other.greenMultiplier);
		addFloat(other.blueMultiplier);
		addFloat(other.alphaMultiplier);
		addFloat(other.redOffset);
		addFloat(other.greenOffset);
		addFloat(other.blueOffset);
		addFloat(other.alphaOffset);
		return this;
	}

	// Internal method for adding bytes
	private inline function __addBytes(bytes:Bytes, offset:Int, length:Int):FastHash
	{
		var end = offset + length;
		for (i in offset...end)
			addByte(bytes.get(i));
		return this;
	}

	public inline function toString():String
	{
		return '0x' + StringTools.hex(this, 8);
	}
}
