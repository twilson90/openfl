package openfl.display._internal;

import openfl.display.DisplayObject;

#if !flash
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class Proxy extends DisplayObject
{
	public var objects:Array<DisplayObject> = [];

	public function new()
	{
		super();
		__drawableType = PROXY;
	}

	public function add(object:DisplayObject)
	{
		objects.push(object);
	}

	public function remove(object:DisplayObject)
	{
		objects.remove(object);
	}
}
#end
