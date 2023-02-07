package main

import "core:fmt"
import win "core:sys/windows"
import glm "core:math/linalg/glsl"
import "core:strings"
import "core:slice"
import "core:c"

import "vendor:glfw"
import DXGI "vendor:directx/dxgi"
import D3D11 "vendor:directx/d3d11"
import D3D "vendor:directx/d3d_compiler"

import "procyon:graphics"

window_width := 960
window_height := 540

framebuffer_size_proc :: proc(window: glfw.WindowHandle, width, height: i32) {
	window_height, window_width = int(height), int(width)
	graphics.on_resize(window_width, window_height)
	graphics.set_viewport(window_width, window_height)
}

main :: proc() {
	glfw.Init()
	defer glfw.Terminate()

	glfw.WindowHint(glfw.SCALE_TO_MONITOR, 0)
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	window := glfw.CreateWindow(c.int(window_width), c.int(window_height), "Hello D3D", nil, nil)
	glfw.SetFramebufferSizeCallback(window, glfw.FramebufferSizeProc(framebuffer_size_proc))
	defer glfw.DestroyWindow(window)

	hwnd := glfw.GetWin32Window(window)

	graphics.initialize(hwnd)
	graphics.set_viewport(window_width, window_height)

	result : DXGI.HRESULT

	texture_desc := D3D11.TEXTURE2D_DESC{
		Width      = TEXTURE_WIDTH,
		Height     = TEXTURE_HEIGHT,
		MipLevels  = 1,
		ArraySize  = 1,
		Format     = .R8G8B8A8_UNORM_SRGB,
		SampleDesc = {Count = 1},
		Usage      = .IMMUTABLE,
		BindFlags  = {.SHADER_RESOURCE},
	}

	texture_data := D3D11.SUBRESOURCE_DATA{
		pSysMem     = &texture_data[0],
		SysMemPitch = TEXTURE_WIDTH * 4,
	}

	texture: ^D3D11.ITexture2D
	graphics.state.device->CreateTexture2D(&texture_desc, &texture_data, &texture)

	texture_view: ^D3D11.IShaderResourceView
	graphics.state.device->CreateShaderResourceView(texture, nil, &texture_view)

	///////////////////////////////////////////////////////////////////////////////////////////////

	mesh := graphics.generate_mesh_cube(1.0, 1.0, 1.0)

	model_rotation    := [3]f32 {0, 0, 0}
	model_position    := [3]f32 {0.0, 0.0, 4.0}

	constant_view := graphics.shader_constant_begin_map(graphics.ShaderConstantView)
	constant_view.matrix_view = glm.identity(glm.mat4)
	graphics.shader_constant_end_map(graphics.ShaderConstantView)

	constant_light := graphics.shader_constant_begin_map(graphics.ShaderConstantLight)
	constant_light.light_vector = {+1, -1, +1}
	graphics.shader_constant_end_map(graphics.ShaderConstantLight)

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		//model_rotation.x += 0.005
		model_rotation.y += 0.009
		//model_rotation.z += 0.001

		graphics.state.device_context->ClearRenderTargetView(graphics.state.framebuffer_view, &[4]f32{0.025, 0.025, 0.025, 1.0})
		graphics.state.device_context->ClearDepthStencilView(graphics.state.depth_buffer_view, {.DEPTH}, 1, 0)

		graphics.state.device_context->VSSetShader(graphics.state.vertex_shader, nil, 0)

		constant_buffers := [?]^D3D11.IBuffer{
			graphics.shader_constants[graphics.ShaderConstantProjection],
			graphics.shader_constants[graphics.ShaderConstantView],
			graphics.shader_constants[graphics.ShaderConstantModel],
			graphics.shader_constants[graphics.ShaderConstantLight],
		}
		graphics.state.device_context->VSSetConstantBuffers(0, len(constant_buffers), &constant_buffers[0])

		graphics.state.device_context->RSSetState(graphics.state.rasterizer_state)

		graphics.state.device_context->PSSetShader(graphics.state.pixel_shader, nil, 0)
		graphics.state.device_context->PSSetShaderResources(0, 1, &texture_view)
		graphics.state.device_context->PSSetSamplers(0, 1, &graphics.state.sampler_state)

		graphics.state.device_context->OMSetRenderTargets(1, &graphics.state.framebuffer_view, graphics.state.depth_buffer_view)
		graphics.state.device_context->OMSetDepthStencilState(graphics.state.depth_stencil_state, 0)
		graphics.state.device_context->OMSetBlendState(nil, nil, ~u32(0)) // use default blend mode (i.e. disable)

		graphics.draw_mesh(&mesh, model_position, model_rotation)

		///////////////////////////////////////////////////////////////////////////////////////////////

		graphics.state.swapchain->Present(1, 0)
	}

	graphics.shutdown()
}

TEXTURE_WIDTH  :: 2
TEXTURE_HEIGHT :: 2

texture_data := [TEXTURE_WIDTH*TEXTURE_HEIGHT]u32{
	0xffffffff, 0xff7f7f7f,
	0xff7f7f7f, 0xffffffff,
}
