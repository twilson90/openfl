package openfl.display._internal;

import openfl.display3D.textures.TextureBase;
import openfl.display._internal.Context3DBitmap;
import openfl.display._internal.Context3DBitmapData;
import openfl.display._internal.Context3DDisplayObject;
import openfl.display._internal.Context3DDisplayObjectContainer;
import openfl.display._internal.Context3DGraphics;
import openfl.display._internal.Context3DMaskShader;
import openfl.display._internal.Context3DSimpleButton;
import openfl.display._internal.Context3DTextField;
import openfl.display._internal.Context3DTilemap;
import openfl.display._internal.Context3DVideo;
import openfl.display._internal.ShaderBuffer;
import openfl.display._internal.Gradient;
import openfl.utils.ObjectPool;
import openfl.display3D.Context3DClearMask;
import openfl.display3D.Context3D;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
import openfl.display.DisplayObject;

@:access(lime.graphics.GLRenderContext)
@:access(openfl.display._internal.ShaderBuffer)
@:access(openfl.display3D.Context3D)
@:access(openfl.display.BitmapData)
@:access(openfl.display.DisplayObject)
@:access(openfl.display.Graphics)
@:access(openfl.display.IBitmapDrawable)
@:access(openfl.display.Shader)
@:access(openfl.display.ShaderParameter)
@:access(openfl.display.Stage3D)
@:access(openfl.geom.ColorTransform)
@:access(openfl.geom.Matrix)
@:access(openfl.geom.Rectangle)
@:access(openfl.filters.BitmapFilter)
class FilterManager
{
	private var renderer:OpenGLRenderer;
	private var __filterDepth:Int = 0;
	private var __renderTexture:TextureBase = null;

	public function new(renderer:OpenGLRenderer)
	{
		this.renderer = renderer;
	}

	public function pushFilters(object:DisplayObject):Void
	{
		if (object.__filters == null || object.__filters.length == 0) return;

		var context = renderer.__context3D;
		var gl = renderer.__gl;

		var bounds = Rectangle.__pool.get();
		object.__getFilterBounds(bounds, object.__renderTransform);

		var w = Math.ceil(bounds.width);
		var h = Math.ceil(bounds.height);

		if (w <= 0 || h <= 0) return;

		if (object.__renderTexture != null)
		{
			object.__renderTexture.__width
		}

		if (object.__renderTexture == null)
		{
			object.__renderTexture = BitmapData.fromTexture(context.createRectangleTexture(w, h, BGRA, true));
		}

		object.__parentRenderTexture = __renderTexture;

		renderer.__setRenderTarget(object.__renderTexture);
		context.clear();

		__filterDepth++;
	}

	public function popFilters(object:DisplayObject):Void
	{
		if (object.__filters == null || object.__filters.length == 0) return;

		var shader:Shader;
		var cacheBitmap:BitmapData;

		for (filter in object.__filters)
		{
			if (filter.__preserveObject)
			{
				renderer.__setRenderTarget(bitmap3);
				childRenderer.__renderFilterPass(bitmap, childRenderer.__defaultDisplayShader, filter.__smooth);
			}

			for (i in 0...filter.__numShaderPasses)
			{
				shader = filter.__initShader(childRenderer, i, filter.__preserveObject ? bitmap3 : null);
				childRenderer.__setBlendMode(filter.__shaderBlendMode);
				childRenderer.__setRenderTarget(bitmap2);
				childRenderer.__renderFilterPass(bitmap, shader, filter.__smooth);

				cacheBitmap = bitmap;
				bitmap = bitmap2;
				bitmap2 = cacheBitmap;
			}

			context.setRenderToTexture(object.__parentRenderTexture);
			__draw();

			__renderTexture = object.__parentRenderTexture;

			__filterDepth--;
		}

		// @:noCompletion private function __renderFilterPass(object:DisplayObject, shader:Shader, smooth:Bool):Void
		// {
		// 	var context = renderer.__context3D;
		// 	var cacheRTT = context.__state.renderToTexture;
		// 	var cacheRTTDepthStencil = context.__state.renderToTextureDepthStencil;
		// 	var cacheRTTAntiAlias = context.__state.renderToTextureAntiAlias;
		// 	var cacheRTTSurfaceSelector = context.__state.renderToTextureSurfaceSelector;
		// 	context.setRenderToTexture(object.__renderTexture, false);
		// 	var shader = renderer.__initShader(shader);
		// 	renderer.setShader(shader);
		// 	renderer.applyAlpha(1);
		// 	// renderer.applyBitmapData(source, smooth);
		// 	// todo: we need to target the object texture...
		// 	renderer.applyColorTransform(null);
		// 	renderer.applyMatrix(renderer.__getMatrix(object.__renderTransform, AUTO));
		// 	renderer.updateShader();
		// 	// todo: get correct vertexbuffer/indexbuffer, or use standard 0-1 texture coordinates, then apply matrix above
		// 	var vertexBuffer = source.getVertexBuffer(context);
		// 	if (shader.__position != null) context.setVertexBufferAt(shader.__position.index, vertexBuffer, 0, FLOAT_3);
		// 	if (shader.__textureCoord != null) context.setVertexBufferAt(shader.__textureCoord.index, vertexBuffer, 3, FLOAT_2);
		// 	var indexBuffer = source.getIndexBuffer(context);
		// 	context.drawTriangles(indexBuffer);
		// 	if (cacheRTT != null)
		// 	{
		// 		context.setRenderToTexture(cacheRTT, cacheRTTDepthStencil, cacheRTTAntiAlias, cacheRTTSurfaceSelector);
		// 	}
		// 	else
		// 	{
		// 		context.setRenderToBackBuffer();
		// 	}
		// 	renderer.__clearShader();
		// }
	}
}
