package openfl.utils._internal;

interface IIndexArray
{
	public var data(get, never):ArrayBufferView;
	public var length(get, never):Int;
	private var __bytesPerElement:Int;
	public function set(i:Int, v:Int):Void;
	public function get(i:Int):Int;
}

class UInt8IndexArray implements IIndexArray
{
	public var length(get, never):Int;
	public var data(get, never):ArrayBufferView;

	private var __bytesPerElement:Int = 1;
	private var __data:UInt8Array;

	public function new(data:UInt8Array = null, initialSize:Int = 0)
	{
		__data = data == null ? new UInt8Array(initialSize) : data;
	}

	public inline function set(i:Int, v:Int):Void
	{
		#if debug if (v < 0 || v > 255) throw 'Index array value out of range'; #end
		__data[i] = v;
	}

	public inline function get(i:Int):Int
	{
		return __data[i];
	}

	private inline function get_length()
	{
		return __data.length;
	}

	private inline function get_data():ArrayBufferView
	{
		return __data;
	}
}

class UInt16IndexArray implements IIndexArray
{
	public var length(get, never):Int;
	public var data(get, never):ArrayBufferView;

	private var __bytesPerElement:Int = 2;
	private var __data:UInt16Array;

	public function new(data:UInt16Array = null, initialSize:Int = 0)
	{
		__data = data == null ? new UInt16Array(initialSize) : data;
	}

	public inline function set(i:Int, v:Int):Void
	{
		#if debug if (v < 0 || v > 65535) throw 'Index array value out of range'; #end
		__data[i] = v;
	}

	public inline function get(i:Int):Int
	{
		return __data[i];
	}

	private inline function get_length()
	{
		return __data.length;
	}

	private inline function get_data():ArrayBufferView
	{
		return __data;
	}
}

class UInt32IndexArray implements IIndexArray
{
	public var length(get, never):Int;
	public var data(get, never):ArrayBufferView;

	private var __bytesPerElement:Int = 4;
	private var __data:UInt32Array;

	public function new(data:UInt32Array = null, initialSize:Int = 0)
	{
		__data = data == null ? new UInt32Array(initialSize) : data;
	}

	public inline function set(i:Int, v:Int):Void
	{
		#if debug if (v < 0 || v > 4294967295) throw 'Index array value out of range'; #end
		__data[i] = v;
	}

	public inline function get(i:Int):Int
	{
		return __data[i];
	}

	private inline function get_length()
	{
		return __data.length;
	}

	private inline function get_data():ArrayBufferView
	{
		return __data;
	}
}

@:forward
@:access(openfl.utils._internal.IIndexArray)
abstract IndexArray(IIndexArray) from IIndexArray to IIndexArray
{
	public var length(get, never):Int;

	public inline function new(length:Int, bytesPerElement:Int)
	{
		switch (bytesPerElement)
		{
			case 1:
				this = new UInt8IndexArray(length);
			case 2:
				this = new UInt16IndexArray(length);
			case 4:
				this = new UInt32IndexArray(length);
			default:
				throw 'Invalid bytes per element';
		}
	}

	public inline function resize(length:Int, bytesPerElement:Int):IndexArray
	{
		var oldData = this;
		var oldLength = this.length;
		if (length > oldLength || bytesPerElement > this.__bytesPerElement)
		{
			var newBuffer = new IndexArray(length, bytesPerElement);
			untyped newBuffer.data.set(oldData.data);
			this = newBuffer;
		}
		return this;
	}

	inline function get_length():Int
	{
		return this.length;
	}

	@:arrayAccess
	public inline function __set(i:Int, v:Int):Void
	{
		this.set(i, v);
	}

	@:arrayAccess
	public inline function __get(i:Int):Int
	{
		return this.get(i);
	}
}
