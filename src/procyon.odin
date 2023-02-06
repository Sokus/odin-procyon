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

Mesh :: struct {
	vertices:  []f32,
	normals:   []f32,
	texcoords: []f32,
	colors:    []u32,
	default_color: bool,
	indices:   []u32,

	position_buffer: ^D3D11.IBuffer,
	normal_buffer: ^D3D11.IBuffer,
	texcoord_buffer: ^D3D11.IBuffer,
	color_buffer: ^D3D11.IBuffer,

	index_buffer: ^D3D11.IBuffer,
}

upload_mesh :: proc(mesh: ^Mesh) {
	vertex_buffer_desc := D3D11.BUFFER_DESC{ Usage = .IMMUTABLE, BindFlags = {.VERTEX_BUFFER} }
	subresource_data: D3D11.SUBRESOURCE_DATA

	assert(len(mesh.vertices) > 0)
	vertices_size := cast(u32)(len(mesh.vertices) * size_of(f32))
	vertex_buffer_desc.ByteWidth = vertices_size
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.vertices[0], SysMemPitch = vertices_size }
	graphics.state.device->CreateBuffer(&vertex_buffer_desc, &subresource_data, &mesh.position_buffer)

	assert(len(mesh.texcoords) > 0)
	texcoords_size := cast(u32)(len(mesh.texcoords) * size_of(f32))
	vertex_buffer_desc.ByteWidth = texcoords_size
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.texcoords[0], SysMemPitch = texcoords_size }
	graphics.state.device->CreateBuffer(&vertex_buffer_desc, &subresource_data, &mesh.texcoord_buffer)

	assert(len(mesh.normals) > 0)
	normals_size := cast(u32)(len(mesh.normals) * size_of(f32))
	vertex_buffer_desc.ByteWidth = normals_size
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.normals[0], SysMemPitch = normals_size }
	graphics.state.device->CreateBuffer(&vertex_buffer_desc, &subresource_data, &mesh.normal_buffer)

	if len(mesh.colors) == 0 {
		mesh.default_color = true
		colors := []u32{ 0xff0000ff }
		mesh.colors = make([]u32, len(colors))
		copy_slice(mesh.colors, colors)
	}

	colors_size := cast(u32)(len(mesh.colors) * size_of(f32))
	vertex_buffer_desc.ByteWidth = colors_size
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.colors[0], SysMemPitch = colors_size }
	graphics.state.device->CreateBuffer(&vertex_buffer_desc, &subresource_data, &mesh.color_buffer)

	indices_size := cast(u32)(len(mesh.indices) * size_of(u32))
	index_buffer_desc := D3D11.BUFFER_DESC{
		Usage = .IMMUTABLE,
		BindFlags = {.INDEX_BUFFER},
		ByteWidth = indices_size,
	}
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.indices[0], SysMemPitch = indices_size }
	graphics.state.device->CreateBuffer(&index_buffer_desc, &subresource_data, &mesh.index_buffer)
}

generate_mesh_cube :: proc (width, height, length: f32) -> (mesh: Mesh) {
	vertices := [?]f32{
		-width/2, -height/2,  length/2,
		 width/2, -height/2,  length/2,
		 width/2,  height/2,  length/2,
		-width/2,  height/2,  length/2,
		-width/2, -height/2, -length/2,
		-width/2,  height/2, -length/2,
		 width/2,  height/2, -length/2,
		 width/2, -height/2, -length/2,
		-width/2,  height/2, -length/2,
		-width/2,  height/2,  length/2,
		 width/2,  height/2,  length/2,
		 width/2,  height/2, -length/2,
		-width/2, -height/2, -length/2,
		 width/2, -height/2, -length/2,
		 width/2, -height/2,  length/2,
		-width/2, -height/2,  length/2,
		 width/2, -height/2, -length/2,
		 width/2,  height/2, -length/2,
		 width/2,  height/2,  length/2,
		 width/2, -height/2,  length/2,
		-width/2, -height/2, -length/2,
		-width/2, -height/2,  length/2,
		-width/2,  height/2,  length/2,
		-width/2,  height/2, -length/2,
	}

	normals := [?]f32{
		 0.0, 0.0, 1.0,  0.0, 0.0, 1.0,  0.0, 0.0, 1.0,  0.0, 0.0, 1.0,
		 0.0, 0.0,-1.0,  0.0, 0.0,-1.0,  0.0, 0.0,-1.0,  0.0, 0.0,-1.0,
		 0.0, 1.0, 0.0,  0.0, 1.0, 0.0,  0.0, 1.0, 0.0,  0.0, 1.0, 0.0,
		 0.0,-1.0, 0.0,  0.0,-1.0, 0.0,  0.0,-1.0, 0.0,  0.0,-1.0, 0.0,
		 1.0, 0.0, 0.0,  1.0, 0.0, 0.0,  1.0, 0.0, 0.0,  1.0, 0.0, 0.0,
		-1.0, 0.0, 0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 0.0, -1.0, 0.0, 0.0,
	}

	texcoords := [?]f32{
		0.0, 0.0,  1.0, 0.0,  1.0, 1.0,  0.0, 1.0,
		1.0, 0.0,  1.0, 1.0,  0.0, 1.0,  0.0, 0.0,
		0.0, 1.0,  0.0, 0.0,  1.0, 0.0,  1.0, 1.0,
		1.0, 1.0,  0.0, 1.0,  0.0, 0.0,  1.0, 0.0,
		1.0, 0.0,  1.0, 1.0,  0.0, 1.0,  0.0, 0.0,
		0.0, 0.0,  1.0, 0.0,  1.0, 1.0,  0.0, 1.0,
	}

	colors := [?]u32{
		0xff007af8,
		0xff007af8,
		0xff007af8,
		0xff007af8,
		0xff0229e4,
		0xff0229e4,
		0xff0229e4,
		0xff0229e4,
		0xff11009c,
		0xff11009c,
		0xff11009c,
		0xff11009c,
		0xff681d20,
		0xff681d20,
		0xff681d20,
		0xff681d20,
		0xffa24000,
		0xffa24000,
		0xffa24000,
		0xffa24000,
		0xff117100,
		0xff117100,
		0xff117100,
		0xff117100,
	}

	indices := [?]u32{
		0,  1,  2,  0,  2,  3,
		4,  5,  6,  4,  6,  7,
		8,  9, 10,  8, 10, 11,
	   12, 13, 14, 12, 14, 15,
	   16, 17, 18, 16, 18, 19,
	   20, 21, 22, 20, 22, 23,
    }

	mesh.vertices = make([]f32, len(vertices))
	copy_slice(mesh.vertices, vertices[:])

	mesh.normals = make([]f32, len(normals))
	copy_slice(mesh.normals, normals[:])

	mesh.texcoords = make([]f32, len(texcoords))
	copy_slice(mesh.texcoords, texcoords[:])

	mesh.colors = make([]u32, len(colors))
	copy_slice(mesh.colors, colors[:])

	mesh.indices = make([]u32, len(indices))
	copy_slice(mesh.indices, indices[:])

	upload_mesh(&mesh)

	return mesh
}

draw_mesh :: proc(mesh: ^Mesh, position: [3]f32, rotation: [3]f32) {
	rotate_x := glm.mat4Rotate({1, 0, 0}, rotation.x)
	rotate_y := glm.mat4Rotate({0, 1, 0}, rotation.y)
	rotate_z := glm.mat4Rotate({0, 0, 1}, rotation.z)
	translate := glm.mat4Translate(glm.vec3{position.x, position.y, position.z})

	constant_model := graphics.shader_constant_begin_map(graphics.ShaderConstantModel)
	constant_model.matrix_model = translate * rotate_z * rotate_y * rotate_x
	graphics.shader_constant_end_map(graphics.ShaderConstantModel)
}

window_width := 960
window_height := 540

framebuffer_size_proc :: proc(window: glfw.WindowHandle, width, height: i32) {
	window_height, window_width = int(height), int(width)
	graphics.on_resize(int(width), int(height))
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

	mesh := generate_mesh_cube(1.0, 1.0, 1.0)

	vertex_buffers := [?]^D3D11.IBuffer {
		mesh.position_buffer,
		mesh.normal_buffer,
		mesh.texcoord_buffer,
		mesh.color_buffer,
	}

	vertex_buffer_strides := [?]u32{
		3 * size_of(f32), // vertices
		3 * size_of(f32), // normals
		2 * size_of(f32), // texcoords
		size_of(u32), // colors
	}

	vertex_buffer_offsets := [?]u32{
		0, 0, 0, 0,
	}

	model_rotation    := [3]f32 {0, 0, 0}
	model_position    := [3]f32 {0.0, 0.0, 4.0}

	{
		constant_view := graphics.shader_constant_begin_map(graphics.ShaderConstantView)
		constant_view.matrix_view = glm.identity(glm.mat4)
		graphics.shader_constant_end_map(graphics.ShaderConstantView)
	}

	{
		constant_light := graphics.shader_constant_begin_map(graphics.ShaderConstantLight)
		constant_light.light_vector = {+1, -1, +1}
		graphics.shader_constant_end_map(graphics.ShaderConstantLight)
	}


	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		viewport := D3D11.VIEWPORT{
			0, 0,
			f32(window_width), f32(window_height),
			0, 1,
		}

		w := viewport.Width / viewport.Height
		h := f32(1)
		n := f32(1)
		f := f32(9)

		model_rotation.x += 0.005
		model_rotation.y += 0.009
		model_rotation.z += 0.001


		{
			constant_projection := graphics.shader_constant_begin_map(graphics.ShaderConstantProjection)
			constant_projection.matrix_projection = {
				2 * n / w, 0,         0,           0,
				0,         2 * n / h, 0,           0,
				0,         0,         f / (f - n), n * f / (n - f),
				0,         0,         1,           0,
			}
			graphics.shader_constant_end_map(graphics.ShaderConstantProjection)
		}

		draw_mesh(&mesh, model_position, model_rotation)

		///////////////////////////////////////////////////////////////////////////////////////////////

		graphics.state.device_context->ClearRenderTargetView(graphics.state.framebuffer_view, &[4]f32{0.025, 0.025, 0.025, 1.0})
		graphics.state.device_context->ClearDepthStencilView(graphics.state.depth_buffer_view, {.DEPTH}, 1, 0)

		graphics.state.device_context->IASetPrimitiveTopology(.TRIANGLELIST)
		graphics.state.device_context->IASetInputLayout(graphics.state.input_layouts[int(mesh.default_color)])
		graphics.state.device_context->IASetVertexBuffers(0, len(vertex_buffers), &vertex_buffers[0], &vertex_buffer_strides[0], &vertex_buffer_offsets[0])
		graphics.state.device_context->IASetIndexBuffer(mesh.index_buffer, .R32_UINT, 0)

		graphics.state.device_context->VSSetShader(graphics.state.vertex_shader, nil, 0)

		constant_buffers := [?]^D3D11.IBuffer{
			graphics.shader_constants[graphics.ShaderConstantProjection],
			graphics.shader_constants[graphics.ShaderConstantView],
			graphics.shader_constants[graphics.ShaderConstantModel],
			graphics.shader_constants[graphics.ShaderConstantLight],
		}
		graphics.state.device_context->VSSetConstantBuffers(0, len(constant_buffers), &constant_buffers[0])

		graphics.state.device_context->RSSetViewports(1, &viewport)
		graphics.state.device_context->RSSetState(graphics.state.rasterizer_state)

		graphics.state.device_context->PSSetShader(graphics.state.pixel_shader, nil, 0)
		graphics.state.device_context->PSSetShaderResources(0, 1, &texture_view)
		graphics.state.device_context->PSSetSamplers(0, 1, &graphics.state.sampler_state)

		graphics.state.device_context->OMSetRenderTargets(1, &graphics.state.framebuffer_view, graphics.state.depth_buffer_view)
		graphics.state.device_context->OMSetDepthStencilState(graphics.state.depth_stencil_state, 0)
		graphics.state.device_context->OMSetBlendState(nil, nil, ~u32(0)) // use default blend mode (i.e. disable)

		///////////////////////////////////////////////////////////////////////////////////////////////

		graphics.state.device_context->DrawIndexed(u32(len(mesh.indices)), 0, 0)

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
