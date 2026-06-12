package openfl.utils._internal;

class LRUCache<V>
{
	public var maxSize:Int;

	var map:Map<Int, V>;
	var keys:Array<Int>;
	var cursor:Int = 0;
	var size:Int = 0;

	public function new(maxSize:Int)
	{
		this.maxSize = maxSize;
		this.map = new Map();
		this.keys = new Array<Int>();

		// preallocate so we never resize in hot path
		keys.resize(maxSize);
	}

	public function get(k:Int):V
	{
		return map.get(k); // Map.get returns null if missing
	}

	public function set(k:Int, v:V)
	{
		// update existing (no eviction change)
		if (map.exists(k))
		{
			map.set(k, v);
			return;
		}

		// if cache not full, just insert
		if (size < maxSize)
		{
			keys[size] = k;
			map.set(k, v);
			size++;
			return;
		}

		// eviction via cyclic overwrite
		var old = keys[cursor];

		if (map.exists(old))
		{
			map.remove(old);
		}

		// overwrite slot
		keys[cursor] = k;
		map.set(k, v);

		cursor++;
		if (cursor >= maxSize) cursor = 0;
	}

	public function exists(k:Int):Bool
	{
		return map.exists(k);
	}
}
