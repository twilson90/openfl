package openfl.utils._internal;

import haxe.ds.IntMap;

class FIFOCache<V>
{
	public var maxSize(get, set):Int;

	private var _maxSize:Int;
	private var _map:IntMap<V>;
	private var _keys:Array<Int>;
	private var _cursor:Int = 0;
	private var _size:Int = 0;
	private var _preallocate:Bool;

	public function new(maxSize:Int, preallocate:Bool = false)
	{
		_maxSize = maxSize;
		_map = new IntMap();
		_preallocate = preallocate;
		_keys = [];

		if (preallocate && maxSize > 0)
		{
			_keys.resize(maxSize);
		}
	}

	private function get_maxSize():Int
	{
		return _maxSize;
	}

	private function set_maxSize(newSize:Int):Int
	{
		if (newSize < 0)
		{
			newSize = 0;
		}

		if (newSize == _maxSize)
		{
			return _maxSize;
		}

		clear();

		_maxSize = newSize;

		if (_preallocate)
		{
			_keys.resize(newSize);
		}
		else
		{
			_keys = [];
		}

		return _maxSize;
	}

	public function get(key:Int):Null<V>
	{
		return _map.get(key);
	}

	public function set(key:Int, value:V):Void
	{
		if (_maxSize <= 0)
		{
			return;
		}

		// Updating an existing entry does not change its FIFO position.
		if (_map.exists(key))
		{
			_map.set(key, value);
			return;
		}

		// Still have unused slots.
		if (_size < _maxSize)
		{
			_keys[_size] = key;
			_map.set(key, value);
			_size++;
			return;
		}

		// Evict oldest entry.
		var oldKey = _keys[_cursor];

		_map.remove(oldKey);

		_keys[_cursor] = key;
		_map.set(key, value);

		_cursor++;

		if (_cursor >= _maxSize)
		{
			_cursor = 0;
		}
	}

	public inline function exists(key:Int):Bool
	{
		return _map.exists(key);
	}

	public function clear():Void
	{
		_map.clear();
		_size = 0;
		_cursor = 0;

		if (!_preallocate)
		{
			_keys = [];
		}
	}

	public inline function size():Int
	{
		return _size;
	}
}
