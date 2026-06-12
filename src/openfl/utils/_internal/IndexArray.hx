package openfl.utils._internal;

interface IIndexArray
{
	public var data(get, never):ArrayBufferView;
	public var length(get, never):Int;
	public var maxVertices(get, never):Int;
	public function set(i:Int, v:Int):Void;
	public function get(i:Int):Int;
}

class UInt8IndexArray implements IIndexArray
{
	public var length(get, never):Int;
	public var data(get, never):ArrayBufferView;
	public var maxVertices(get, never):Int;

	private var __data:UInt8Array;

	public function new(data:UInt8Array = null, initialSize:Int = 0)
	{
		__data = data == null ? new UInt8Array(initialSize) : data;
	}

	public inline function set(i:Int, v:Int):Void
	{
		__data[i] = v;
	}

	public inline function get(i:Int):Int
	{
		return __data[i];
	}

	public inline function get_maxVertices()
	{
		return 255;
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
	public var maxVertices(get, never):Int;

	private var __data:UInt16Array;

	public function new(data:UInt16Array = null, initialSize:Int = 0)
	{
		__data = data == null ? new UInt16Array(initialSize) : data;
	}

	public inline function set(i:Int, v:Int):Void
	{
		__data[i] = v;
	}

	public inline function get(i:Int):Int
	{
		return __data[i];
	}

	public inline function get_maxVertices()
	{
		return 65535;
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
	public var maxVertices(get, never):Int;

	private var __data:UInt32Array;

	public function new(data:UInt32Array = null, initialSize:Int = 0)
	{
		__data = data == null ? new UInt32Array(initialSize) : data;
	}

	public inline function set(i:Int, v:Int):Void
	{
		__data[i] = v;
	}

	public inline function get(i:Int):Int
	{
		return __data[i];
	}

	public inline function get_maxVertices()
	{
		return 0x7fffffff;
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
abstract IndexArray(IIndexArray) from IIndexArray to IIndexArray
{
	public var length(get, never):Int;

	public inline function new(length:Int, maxVertices:Int)
	{
		this = maxVertices > 65535 ? new UInt32IndexArray(null,
			length) : maxVertices > 255 ? new UInt16IndexArray(null, length) : new UInt8IndexArray(null, length);
	}

	public inline function resize(length:Int, maxVertices:Int)
	{
		if (length < this.length) throw 'Index array length cannot be reduced';
		var oldData = this.data;
		var newBuffer = new IndexArray(length, maxVertices);
		newBuffer.data.set(oldData);
		this = newBuffer;
	}

	public static inline function from(data:ArrayBufferView):IndexArray
	{
		switch (data.type)
		{
			case lime.utils.ArrayBufferView.TypedArrayType.Uint32:
				return new UInt32IndexArray(data);
			case lime.utils.ArrayBufferView.TypedArrayType.Uint8:
				return new UInt8IndexArray(data);
			case lime.utils.ArrayBufferView.TypedArrayType.Uint16:
				return new UInt16IndexArray(data);
			default:
				throw 'Invalid index array type: ${data.type}';
		}
	}

	inline function get_length()
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
