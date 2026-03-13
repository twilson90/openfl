package openfl.utils;

class ArrayUtil
{
	static public inline function resize<T>(array:Array<T>, length:Int):Void
	{
		var oldLength = array.length;
		if (oldLength == length) return;
		#if haxe4
		array.resize(length);
		#else
		array.splice(0, oldLength);
		#end
	}

	static public inline function clear<T>(array:Array<T>):Void
	{
		resize(array, 0);
	}

	static public inline function copyFrom<T>(dest:Array<T>, src:Array<T>):Void
	{
		resize(dest, src.length);
		for (i in 0...src.length)
		{
			dest[i] = src[i];
		}
	}

	static public function equals<T>(a:Array<T>, b:Array<T>):Bool
	{
		if (a.length != b.length) return false;
		for (i in 0...a.length)
		{
			if (a[i] != b[i]) return false;
		}
		return true;
	}
}
