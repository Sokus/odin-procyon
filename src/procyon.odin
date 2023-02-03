package main

import "core:fmt"
import win "core:sys/windows"
import glm "core:math/linalg/glsl"
import "core:strings"
import "core:slice"

import "vendor:glfw"
import DXGI "vendor:directx/dxgi"
import D3D11 "vendor:directx/d3d11"
import D3D "vendor:directx/d3d_compiler"

compile_shader :: proc(file_name, entry_point, profile: string) -> (shader_blob: ^D3D11.IBlob) {
	compiler_flags := D3D.D3DCOMPILE.ENABLE_STRICTNESS
	error_blob : ^D3D11.IBlob

	wchar_file_name := win.utf8_to_wstring(file_name)
	cstr_entry_point := strings.clone_to_cstring(entry_point, context.temp_allocator)
	cstr_profile := strings.clone_to_cstring(profile, context.temp_allocator)

	result := D3D.CompileFromFile(wchar_file_name, nil, nil, cstr_entry_point, cstr_profile, u32(compiler_flags), 0, &shader_blob, &error_blob)
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to read shader from file (0x%x)\n", u32(result))
		if error_blob != nil {
			msg := error_blob->GetBufferPointer()
			fmt.printf("\tWith message: %v\n", cstring(msg))
		}
		return nil
	}
	return shader_blob
}

create_vertex_shader :: proc(device: ^D3D11.IDevice, file_name: string) -> (vertex_shader : ^D3D11.IVertexShader, vertex_shader_blob : ^D3D11.IBlob) {
	vertex_shader_blob = compile_shader(file_name, "vs_main", "vs_5_0")
	if vertex_shader_blob == nil {
		return nil, nil
	}

	result := device->CreateVertexShader(vertex_shader_blob->GetBufferPointer(), vertex_shader_blob->GetBufferSize(), nil, &vertex_shader)
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to compile vertex shader (0x%x)\n", u32(result))
		return nil, nil
	}

	return vertex_shader, vertex_shader_blob
}

create_pixel_shader :: proc(device: ^D3D11.IDevice, file_name: string) -> (pixel_shader : ^D3D11.IPixelShader, pixel_shader_blob : ^D3D11.IBlob) {
	pixel_shader_blob = compile_shader(file_name, "ps_main", "ps_5_0")
	if pixel_shader_blob == nil {
		return nil, nil
	}

	result := device->CreatePixelShader(pixel_shader_blob->GetBufferPointer(), pixel_shader_blob->GetBufferSize(), nil, &pixel_shader)
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to compile pixel shader (0x%x)\n", u32(result))
		return nil, nil
	}

	return pixel_shader, pixel_shader_blob
}

MeshVertexBuffer :: enum {
	Position,
	Normal,
	Texcoord,
	Color,
}

Mesh :: struct {
	vertices:  []f32,
	texcoords: []f32,
	normals:   []f32,
	colors:    []f32,
	indices:   []u32,

	vertex_buffers: [MeshVertexBuffer]^D3D11.IBuffer,
	index_buffer: ^D3D11.IBuffer,

	input_layout: ^D3D11.IInputLayout,
}

State :: struct {
	device: ^D3D11.IDevice,

	vs_blob, ps_blob: ^D3D11.IBlob,
	vertex_shader: ^D3D11.IVertexShader,
	pixel_shader: ^D3D11.IPixelShader,

	input_layout: ^D3D11.IInputLayout,
}

state: State

upload_mesh :: proc(mesh: ^Mesh) {
	for mesh_vertex_buffer in MeshVertexBuffer {
		assert(mesh.vertex_buffers[mesh_vertex_buffer] == nil, "Failed to upload mesh, buffer already initialized")
	}

	input_element_desc := [?]D3D11.INPUT_ELEMENT_DESC{
		{ "POS", 0, .R32G32B32_FLOAT, 0,                            0, .VERTEX_DATA, 0 },
		{ "NOR", 0, .R32G32B32_FLOAT, 1, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
		{ "TEX", 0, .R32G32_FLOAT,    2, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
		{ "COL", 0, .R32G32B32_FLOAT, 3, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA if len(mesh.colors) > 0 else .INSTANCE_DATA, 0 },
	}

	vertex_buffer_desc := D3D11.BUFFER_DESC{ Usage = .IMMUTABLE, BindFlags = {.VERTEX_BUFFER} }
	subresource_data: D3D11.SUBRESOURCE_DATA

	assert(len(mesh.vertices) > 0)
	vertices_size := cast(u32)(len(mesh.vertices) * size_of(f32))
	vertex_buffer_desc.ByteWidth = vertices_size
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.vertices[0], SysMemPitch = vertices_size }
	state.device->CreateBuffer(&vertex_buffer_desc, &subresource_data, &mesh.vertex_buffers[.Position])

	assert(len(mesh.texcoords) > 0)
	texcoords_size := cast(u32)(len(mesh.texcoords) * size_of(f32))
	vertex_buffer_desc.ByteWidth = texcoords_size
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.texcoords[0], SysMemPitch = texcoords_size }
	state.device->CreateBuffer(&vertex_buffer_desc, &subresource_data, &mesh.vertex_buffers[.Texcoord])

	assert(len(mesh.normals) > 0)
	normals_size := cast(u32)(len(mesh.normals) * size_of(f32))
	vertex_buffer_desc.ByteWidth = normals_size
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.normals[0], SysMemPitch = normals_size }
	state.device->CreateBuffer(&vertex_buffer_desc, &subresource_data, &mesh.vertex_buffers[.Normal])

	if len(mesh.colors) == 0 {
		colors := []f32{ 1.0, 1.0, 1.0 }
		mesh.colors = make([]f32, len(colors))
		copy_slice(mesh.colors, colors)
	}

	colors_size := cast(u32)(len(mesh.colors) * size_of(f32))
	vertex_buffer_desc.ByteWidth = colors_size
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.colors[0], SysMemPitch = colors_size }
	state.device->CreateBuffer(&vertex_buffer_desc, &subresource_data, &mesh.vertex_buffers[.Color])

	indices_size := cast(u32)(len(mesh.indices) * size_of(u32))
	index_buffer_desc := D3D11.BUFFER_DESC{
		Usage = .IMMUTABLE,
		BindFlags = {.INDEX_BUFFER},
		ByteWidth = indices_size,
	}
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.indices[0], SysMemPitch = indices_size }
	state.device->CreateBuffer(&index_buffer_desc, &subresource_data, &mesh.index_buffer)

	state.device->CreateInputLayout(&input_element_desc[0], len(input_element_desc), state.vs_blob->GetBufferPointer(), state.vs_blob->GetBufferSize(), &mesh.input_layout)
}

generate_mesh_cube :: proc(width, height, length: f32) -> (mesh: Mesh) {
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

	colors := [?]f32{
		0.973,  0.480,  0.002,
		0.973,  0.480,  0.002,
		0.973,  0.480,  0.002,
		0.973,  0.480,  0.002,
		0.897,  0.163,  0.011,
		0.897,  0.163,  0.011,
		0.897,  0.163,  0.011,
		0.897,  0.163,  0.011,
		0.612,  0.000,  0.069,
		0.612,  0.000,  0.069,
		0.612,  0.000,  0.069,
		0.612,  0.000,  0.069,
		0.127,  0.116,  0.408,
		0.127,  0.116,  0.408,
		0.127,  0.116,  0.408,
		0.127,  0.116,  0.408,
		0.000,  0.254,  0.637,
		0.000,  0.254,  0.637,
		0.000,  0.254,  0.637,
		0.000,  0.254,  0.637,
		0.001,  0.447,  0.067,
		0.001,  0.447,  0.067,
		0.001,  0.447,  0.067,
		0.001,  0.447,  0.067,
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

	mesh.colors = make([]f32, len(colors))
	copy_slice(mesh.colors, colors[:])

	mesh.indices = make([]u32, len(indices))
	copy_slice(mesh.indices, indices[:])

	upload_mesh(&mesh)

	return mesh
}

main :: proc() {
	glfw.Init()
	defer glfw.Terminate()

	glfw.WindowHint(glfw.SCALE_TO_MONITOR, 0)
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	window := glfw.CreateWindow(960, 540, "Hello D3D", nil, nil)
	defer glfw.DestroyWindow(window)

	hwnd := glfw.GetWin32Window(window)

	result : DXGI.HRESULT

	base_device: ^D3D11.IDevice
	base_device_context: ^D3D11.IDeviceContext

	feature_levels := [?]D3D11.FEATURE_LEVEL{._11_0}
	result = D3D11.CreateDevice(nil, .HARDWARE, nil, {.BGRA_SUPPORT}, &feature_levels[0], len(feature_levels), D3D11.SDK_VERSION, &base_device, nil, &base_device_context)
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to create Device and Device Context (0x%x)\n", u32(result))
		return
	}

	result = base_device->QueryInterface(D3D11.IDevice_UUID, (^rawptr)(&state.device))

	device_context: ^D3D11.IDeviceContext
	base_device_context->QueryInterface(D3D11.IDeviceContext_UUID, (^rawptr)(&device_context))

	dxgi_device: ^DXGI.IDevice
	state.device->QueryInterface(DXGI.IDevice_UUID, (^rawptr)(&dxgi_device))

	dxgi_adapter: ^DXGI.IAdapter
	dxgi_device->GetAdapter(&dxgi_adapter)

	dxgi_factory: ^DXGI.IFactory2
	dxgi_adapter->GetParent(DXGI.IFactory2_UUID, (^rawptr)(&dxgi_factory))

	///////////////////////////////////////////////////////////////////////////////////////////////

	swapchain_desc := DXGI.SWAP_CHAIN_DESC1{
		Width  = 0,
		Height = 0,
		Format = .B8G8R8A8_UNORM_SRGB,
		Stereo = false,
		SampleDesc = {
			Count   = 1,
			Quality = 0,
		},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		BufferCount = 2,
		Scaling     = .STRETCH,
		SwapEffect  = .DISCARD,
		AlphaMode   = .UNSPECIFIED,
		Flags       = 0,
	}

	swapchain: ^DXGI.ISwapChain1
	result = dxgi_factory->CreateSwapChainForHwnd(state.device, hwnd, &swapchain_desc, nil, nil, &swapchain)
	if !win.SUCCEEDED(result) {
		fmt.printf("DXGI: Failed to create Swapchain (0x%x)\n", u32(result))
		return
	}
	defer swapchain->Release()

	framebuffer: ^D3D11.ITexture2D
	result = swapchain->GetBuffer(0, D3D11.ITexture2D_UUID, (^rawptr)(&framebuffer))
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to get Framebuffer form swapchain (0x%x)\n", u32(result))
		return;
	}
	defer framebuffer->Release()

	framebuffer_view: ^D3D11.IRenderTargetView
	result = state.device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view)
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to create Render Target View (0x%x)\n", u32(result))
		return
	}
	defer framebuffer_view->Release()

	depth_buffer_desc: D3D11.TEXTURE2D_DESC
	framebuffer->GetDesc(&depth_buffer_desc)
	depth_buffer_desc.Format = .D24_UNORM_S8_UINT
	depth_buffer_desc.BindFlags = {.DEPTH_STENCIL}

	depth_buffer: ^D3D11.ITexture2D
	result = state.device->CreateTexture2D(&depth_buffer_desc, nil, &depth_buffer)
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to create Depth Buffer (0x%x)\n", u32(result))
		return
	}
	defer depth_buffer->Release()

	depth_buffer_view: ^D3D11.IDepthStencilView
	result = state.device->CreateDepthStencilView(depth_buffer, nil, &depth_buffer_view)
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to create Depth Stencil View (0x%x)\n", u32(result))
		return
	}
	defer depth_buffer_view->Release();

	///////////////////////////////////////////////////////////////////////////////////////////////

	state.vertex_shader, state.vs_blob = create_vertex_shader(state.device, "assets/shader.hlsl")
	assert(state.vs_blob != nil)

	input_element_desc := [?]D3D11.INPUT_ELEMENT_DESC{
		{ "POS", 0, .R32G32B32_FLOAT, 0,                            0, .VERTEX_DATA, 0 },
		{ "NOR", 0, .R32G32B32_FLOAT, 1, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
		{ "TEX", 0, .R32G32_FLOAT,    2, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
		{ "COL", 0, .R32G32B32_FLOAT, 3, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
	}

	state.pixel_shader, state.ps_blob = create_pixel_shader(state.device, "assets/shader.hlsl")

	///////////////////////////////////////////////////////////////////////////////////////////////

	rasterizer_desc := D3D11.RASTERIZER_DESC{
		FillMode = .SOLID,
		CullMode = .BACK,
	}
	rasterizer_state: ^D3D11.IRasterizerState
	result = state.device->CreateRasterizerState(&rasterizer_desc, &rasterizer_state)

	sampler_desc := D3D11.SAMPLER_DESC{
		Filter         = .MIN_MAG_MIP_POINT,
		AddressU       = .WRAP,
		AddressV       = .WRAP,
		AddressW       = .WRAP,
		ComparisonFunc = .NEVER,
	}
	sampler_state: ^D3D11.ISamplerState
	state.device->CreateSamplerState(&sampler_desc, &sampler_state)

	depth_stencil_desc := D3D11.DEPTH_STENCIL_DESC{
		DepthEnable    = true,
		DepthWriteMask = .ALL,
		DepthFunc      = .LESS,
	}
	depth_stencil_state: ^D3D11.IDepthStencilState
	state.device->CreateDepthStencilState(&depth_stencil_desc, &depth_stencil_state)

	///////////////////////////////////////////////////////////////////////////////////////////////

	Constants :: struct #align 16 {
		transform:    glm.mat4,
		projection:   glm.mat4,
		light_vector: glm.vec3,
	}

	constant_buffer_desc := D3D11.BUFFER_DESC{
		ByteWidth      = size_of(Constants),
		Usage          = .DYNAMIC,
		BindFlags      = {.CONSTANT_BUFFER},
		CPUAccessFlags = {.WRITE},
	}
	constant_buffer: ^D3D11.IBuffer
	state.device->CreateBuffer(&constant_buffer_desc, nil, &constant_buffer)

	///////////////////////////////////////////////////////////////////////////////////////////////

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
	state.device->CreateTexture2D(&texture_desc, &texture_data, &texture)

	texture_view: ^D3D11.IShaderResourceView
	state.device->CreateShaderResourceView(texture, nil, &texture_view)

	///////////////////////////////////////////////////////////////////////////////////////////////

	mesh := generate_mesh_cube(1.0, 1.0, 1.0)

	vertex_buffer_strides := [?]u32{
		3 * size_of(f32), // vertices
		3 * size_of(f32), // normals
		2 * size_of(f32), // texcoords
		3 * size_of(f32), // colors
	}

	vertex_buffer_offsets := [?]u32{
		0, 0, 0, 0,
	}

	model_rotation    := glm.vec3{0.0, 0.0, 0.0}
	model_translation := glm.vec3{0.0, 0.0, 4.0}


	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		viewport := D3D11.VIEWPORT{
			0, 0,
			f32(depth_buffer_desc.Width), f32(depth_buffer_desc.Height),
			0, 1,
		}

		w := viewport.Width / viewport.Height
		h := f32(1)
		n := f32(1)
		f := f32(9)

		rotate_x := glm.mat4Rotate({1, 0, 0}, model_rotation.x)
		rotate_y := glm.mat4Rotate({0, 1, 0}, model_rotation.y)
		rotate_z := glm.mat4Rotate({0, 0, 1}, model_rotation.z)
		translate := glm.mat4Translate(model_translation)

		model_rotation.x += 0.005
		model_rotation.y += 0.009
		model_rotation.z += 0.001

		mapped_subresource: D3D11.MAPPED_SUBRESOURCE
		device_context->Map(constant_buffer, 0, .WRITE_DISCARD, {}, &mapped_subresource)
		{
			constants := (^Constants)(mapped_subresource.pData)
			constants.transform = translate * rotate_z * rotate_y * rotate_x
			constants.light_vector = {+1, -1, +1}

			constants.projection = {
				2 * n / w, 0,         0,           0,
				0,         2 * n / h, 0,           0,
				0,         0,         f / (f - n), n * f / (n - f),
				0,         0,         1,           0,
			}
		}
		device_context->Unmap(constant_buffer, 0)

		///////////////////////////////////////////////////////////////////////////////////////////////

		device_context->ClearRenderTargetView(framebuffer_view, &[4]f32{0.025, 0.025, 0.025, 1.0})
		device_context->ClearDepthStencilView(depth_buffer_view, {.DEPTH}, 1, 0)

		device_context->IASetPrimitiveTopology(.TRIANGLELIST)
		//device_context->IASetInputLayout(input_layout)
		//device_context->IASetVertexBuffers(0, len(vertex_buffers), &vertex_buffers[0], &vertex_buffer_strides[0], &vertex_buffer_offsets[0])
		device_context->IASetInputLayout(mesh.input_layout)
		device_context->IASetVertexBuffers(0, len(mesh.vertex_buffers), &mesh.vertex_buffers[MeshVertexBuffer(0)], &vertex_buffer_strides[0], &vertex_buffer_offsets[0])
		//device_context->IASetIndexBuffer(index_buffer, .R32_UINT, 0)
		device_context->IASetIndexBuffer(mesh.index_buffer, .R32_UINT, 0)

		device_context->VSSetShader(state.vertex_shader, nil, 0)
		device_context->VSSetConstantBuffers(0, 1, &constant_buffer)

		device_context->RSSetViewports(1, &viewport)
		device_context->RSSetState(rasterizer_state)

		device_context->PSSetShader(state.pixel_shader, nil, 0)
		device_context->PSSetShaderResources(0, 1, &texture_view)
		device_context->PSSetSamplers(0, 1, &sampler_state)

		device_context->OMSetRenderTargets(1, &framebuffer_view, depth_buffer_view)
		device_context->OMSetDepthStencilState(depth_stencil_state, 0)
		device_context->OMSetBlendState(nil, nil, ~u32(0)) // use default blend mode (i.e. disable)

		///////////////////////////////////////////////////////////////////////////////////////////////

		device_context->DrawIndexed(u32(len(mesh.indices)), 0, 0)

		swapchain->Present(1, 0)
	}
}

TEXTURE_WIDTH  :: 2
TEXTURE_HEIGHT :: 2

texture_data := [TEXTURE_WIDTH*TEXTURE_HEIGHT]u32{
	0xffffffff, 0xff7f7f7f,
	0xff7f7f7f, 0xffffffff,
}

// color: float3
colors2 := [?]f32{
	0.973,  0.480,  0.002,
	0.973,  0.480,  0.002,
	0.973,  0.480,  0.002,
	0.973,  0.480,  0.002,
	0.897,  0.163,  0.011,
	0.897,  0.163,  0.011,
	0.897,  0.163,  0.011,
	0.897,  0.163,  0.011,
	0.612,  0.000,  0.069,
	0.612,  0.000,  0.069,
	0.612,  0.000,  0.069,
	0.612,  0.000,  0.069,
	0.127,  0.116,  0.408,
	0.127,  0.116,  0.408,
	0.127,  0.116,  0.408,
	0.127,  0.116,  0.408,
	0.000,  0.254,  0.637,
	0.000,  0.254,  0.637,
	0.000,  0.254,  0.637,
	0.000,  0.254,  0.637,
	0.001,  0.447,  0.067,
	0.001,  0.447,  0.067,
	0.001,  0.447,  0.067,
	0.001,  0.447,  0.067,
}
