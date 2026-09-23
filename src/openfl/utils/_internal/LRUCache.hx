package openfl.utils._internal;

import haxe.ds.IntMap;

class LRUCache<V>
{
	public var maxSize(get, set):Int;

	private var _maxSize:Int;
	private var _map:IntMap<Node<V>>;
	private var _head:Node<V>;
	private var _tail:Node<V>;
	private var _size:Int = 0;

	public function new(maxSize:Int)
	{
		_maxSize = maxSize;
		_map = new IntMap<Node<V>>();
	}

	private function get_maxSize():Int
	{
		return _maxSize;
	}

	private function set_maxSize(newSize:Int):Int
	{
		if (newSize < 0) newSize = 0;
		if (newSize == _maxSize) return _maxSize;

		_maxSize = newSize;

		while (_size > _maxSize)
		{
			removeHead();
		}

		return _maxSize;
	}

	public function get(key:Int):Null<V>
	{
		var node = _map.get(key);

		if (node == null)
		{
			return null;
		}

		moveToTail(node);
		return node.value;
	}

	public function set(key:Int, value:V):Void
	{
		if (_maxSize <= 0) return;

		var node = _map.get(key);

		if (node != null)
		{
			node.value = value;
			moveToTail(node);
			return;
		}

		if (_size >= _maxSize)
		{
			removeHead();
		}

		node = new Node(key, value);

		_map.set(key, node);
		appendTail(node);
		_size++;
	}

	public inline function exists(key:Int):Bool
	{
		return _map.exists(key);
	}

	public function clear():Void
	{
		_map.clear();
		_head = null;
		_tail = null;
		_size = 0;
	}

	public inline function size():Int
	{
		return _size;
	}

	private inline function appendTail(node:Node<V>):Void
	{
		node.prev = _tail;
		node.next = null;

		if (_tail != null)
		{
			_tail.next = node;
		}
		else
		{
			_head = node;
		}

		_tail = node;
	}

	private inline function removeHead():Void
	{
		var node = _head;

		if (node == null) return;

		_map.remove(node.key);

		_head = node.next;

		if (_head != null)
		{
			_head.prev = null;
		}
		else
		{
			_tail = null;
		}

		node.prev = null;
		node.next = null;

		_size--;
	}

	private inline function moveToTail(node:Node<V>):Void
	{
		if (node == _tail) return;

		if (node.prev != null)
		{
			node.prev.next = node.next;
		}
		else
		{
			_head = node.next;
		}

		if (node.next != null)
		{
			node.next.prev = node.prev;
		}

		node.prev = _tail;
		node.next = null;

		if (_tail != null)
		{
			_tail.next = node;
		}

		_tail = node;
	}
}

private class Node<V>
{
	public var key:Int;
	public var value:V;
	public var prev:Node<V>;
	public var next:Node<V>;

	public inline function new(key:Int, value:V)
	{
		this.key = key;
		this.value = value;
	}
}
