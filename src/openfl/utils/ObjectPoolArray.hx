package openfl.utils;

class ObjectPoolArray<T>
{
	public var position(get, never):Int;
	public var capacity(get, never):Int;

	@:noCompletion private var __data:Array<T>;
	@:noCompletion private var __current:Int = 0;
	@:noCompletion private var __position:Int = 0;
	@:noCompletion private var __iterator:ObjectPoolArrayIterator<T>;

	public function new(create:Void->T = null, clean:T->Void = null)
	{
		__data = [];
		__iterator = new ObjectPoolArrayIterator<T>(this);

		if (create != null) this.create = create;

		if (clean != null) this.clean = clean;
	}

	public function reset():Void
	{
		for (i in 0...__position)
		{
			clean(__data[i]);
		}
		__position = 0;
	}

	public function get():T
	{
		__position++;
		if (__position > __data.length)
		{
			var object = create();
			__data.push(object);
			return object;
		}
		return __data[__position - 1];
	}

	public function iterator():ObjectPoolArrayIterator<T>
	{
		__iterator.reset();
		return __iterator;
	}

	public dynamic function create():T
	{
		return null;
	}

	public dynamic function clean(object:T):Void {}

	public function get_position():Int
	{
		return __position;
	}

	public function get_capacity():Int
	{
		return __data.length;
	}
}

@:access(openfl.utils.ObjectPoolArray)
class ObjectPoolArrayIterator<T>
{
	private var __pool:ObjectPoolArray<T>;
	private var __index:Int = 0;

	public inline function new(pool:ObjectPoolArray<T>)
	{
		__pool = pool;
	}

	public inline function reset():Void
	{
		__index = 0;
	}

	public inline function hasNext():Bool
	{
		return __index < __pool.__position;
	}

	public inline function next():T
	{
		return __pool.__data[__index++];
	}
}
