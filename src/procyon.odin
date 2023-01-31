package main

import "core:fmt"
import win "core:sys/windows"
import glm "core:math/linalg/glsl"
import "core:strings"

import "vendor:glfw"
import DXGI "vendor:directx/dxgi"
import D3D11 "vendor:directx/d3d11"
import D3D "vendor:directx/d3d_compiler"

// Based off https://gist.github.com/d7samurai/261c69490cce0620d0bfc93003cd1052

compile_shader :: proc(file_name, entry_point, profile : string) -> (shader_blob : ^D3D11.IBlob) {
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

create_vertex_shader :: proc(device : ^D3D11.IDevice, file_name : string) -> (vertex_shader : ^D3D11.IVertexShader, vertex_shader_blob : ^D3D11.IBlob) {
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

create_pixel_shader :: proc(device : ^D3D11.IDevice, file_name : string) -> (pixel_shader : ^D3D11.IPixelShader, pixel_shader_blob : ^D3D11.IBlob) {
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

	device: ^D3D11.IDevice
	result = base_device->QueryInterface(D3D11.IDevice_UUID, (^rawptr)(&device))

	device_context: ^D3D11.IDeviceContext
	base_device_context->QueryInterface(D3D11.IDeviceContext_UUID, (^rawptr)(&device_context))

	dxgi_device: ^DXGI.IDevice
	device->QueryInterface(DXGI.IDevice_UUID, (^rawptr)(&dxgi_device))

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
	result = dxgi_factory->CreateSwapChainForHwnd(device, hwnd, &swapchain_desc, nil, nil, &swapchain)
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
	result = device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view)
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
	result = device->CreateTexture2D(&depth_buffer_desc, nil, &depth_buffer)
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to create Depth Buffer (0x%x)\n", u32(result))
		return
	}
	defer depth_buffer->Release()

	depth_buffer_view: ^D3D11.IDepthStencilView
	result = device->CreateDepthStencilView(depth_buffer, nil, &depth_buffer_view)
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to create Depth Stencil View (0x%x)\n", u32(result))
		return
	}
	defer depth_buffer_view->Release();

	///////////////////////////////////////////////////////////////////////////////////////////////

	vertex_shader, vs_blob := create_vertex_shader(device, "assets/shader.hlsl")
	assert(vs_blob != nil)

	input_element_desc := [?]D3D11.INPUT_ELEMENT_DESC{
		{ "POS", 0, .R32G32B32_FLOAT, 0,                            0, .VERTEX_DATA, 0 },
		{ "NOR", 0, .R32G32B32_FLOAT, 0, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
		{ "TEX", 0, .R32G32_FLOAT,    0, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
		{ "COL", 0, .R32G32B32_FLOAT, 0, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
	}

	input_layout: ^D3D11.IInputLayout
	device->CreateInputLayout(&input_element_desc[0], len(input_element_desc), vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), &input_layout)

	pixel_shader, ps_blob := create_pixel_shader(device, "assets/shader.hlsl")

	///////////////////////////////////////////////////////////////////////////////////////////////

	rasterizer_desc := D3D11.RASTERIZER_DESC{
		FillMode = .SOLID,
		CullMode = .BACK,
	}
	rasterizer_state: ^D3D11.IRasterizerState
	result = device->CreateRasterizerState(&rasterizer_desc, &rasterizer_state)


	sampler_desc := D3D11.SAMPLER_DESC{
		Filter         = .MIN_MAG_MIP_POINT,
		AddressU       = .WRAP,
		AddressV       = .WRAP,
		AddressW       = .WRAP,
		ComparisonFunc = .NEVER,
	}
	sampler_state: ^D3D11.ISamplerState
	device->CreateSamplerState(&sampler_desc, &sampler_state)


	depth_stencil_desc := D3D11.DEPTH_STENCIL_DESC{
		DepthEnable    = true,
		DepthWriteMask = .ALL,
		DepthFunc      = .LESS,
	}
	depth_stencil_state: ^D3D11.IDepthStencilState
	device->CreateDepthStencilState(&depth_stencil_desc, &depth_stencil_state)

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
	device->CreateBuffer(&constant_buffer_desc, nil, &constant_buffer)

	vertex_buffer_desc := D3D11.BUFFER_DESC{
		ByteWidth = size_of(vertex_data),
		Usage     = .IMMUTABLE,
		BindFlags = {.VERTEX_BUFFER},
	}

	vertex_subresource_data := D3D11.SUBRESOURCE_DATA{
		pSysMem = &vertex_data[0],
		SysMemPitch = size_of(vertex_data),
	}

	vertex_buffer: ^D3D11.IBuffer
	device->CreateBuffer(&vertex_buffer_desc, &vertex_subresource_data, &vertex_buffer)

	index_buffer_desc := D3D11.BUFFER_DESC{
		ByteWidth = size_of(index_data),
		Usage     = .IMMUTABLE,
		BindFlags = {.INDEX_BUFFER},
	}

	index_subresource_data := D3D11.SUBRESOURCE_DATA{
		pSysMem = &index_data[0],
		SysMemPitch = size_of(index_data),
	}

	index_buffer: ^D3D11.IBuffer
	device->CreateBuffer(&index_buffer_desc, &index_subresource_data, &index_buffer)

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
	device->CreateTexture2D(&texture_desc, &texture_data, &texture)

	texture_view: ^D3D11.IShaderResourceView
	device->CreateShaderResourceView(texture, nil, &texture_view)

	///////////////////////////////////////////////////////////////////////////////////////////////

	vertex_buffer_stride := u32(11 * 4)
	vertex_buffer_offset := u32(0)

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
		device_context->IASetInputLayout(input_layout)
		device_context->IASetVertexBuffers(0, 1, &vertex_buffer, &vertex_buffer_stride, &vertex_buffer_offset)
		device_context->IASetIndexBuffer(index_buffer, .R32_UINT, 0)

		device_context->VSSetShader(vertex_shader, nil, 0)
		device_context->VSSetConstantBuffers(0, 1, &constant_buffer)

		device_context->RSSetViewports(1, &viewport)
		device_context->RSSetState(rasterizer_state)

		device_context->PSSetShader(pixel_shader, nil, 0)
		device_context->PSSetShaderResources(0, 1, &texture_view)
		device_context->PSSetSamplers(0, 1, &sampler_state)

		device_context->OMSetRenderTargets(1, &framebuffer_view, depth_buffer_view)
		device_context->OMSetDepthStencilState(depth_stencil_state, 0)
		device_context->OMSetBlendState(nil, nil, ~u32(0)) // use default blend mode (i.e. disable)

		///////////////////////////////////////////////////////////////////////////////////////////////

		device_context->DrawIndexed(len(index_data), 0, 0)

		swapchain->Present(1, 0)
	}
}

TEXTURE_WIDTH  :: 2
TEXTURE_HEIGHT :: 2

texture_data := [TEXTURE_WIDTH*TEXTURE_HEIGHT]u32{
	0xffffffff, 0xff7f7f7f,
	0xff7f7f7f, 0xffffffff,
}

// position: float3, normal: float3, texcoord: float2, color: float3
vertex_data := [?]f32{
	-1.0,  1.0, -1.0,  0.0,  0.0, -1.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	-0.6,  1.0, -1.0,  0.0,  0.0, -1.0,  2.0,  0.0,  0.973,  0.480,  0.002,
	 0.6,  1.0, -1.0,  0.0,  0.0, -1.0,  8.0,  0.0,  0.973,  0.480,  0.002,
	 1.0,  1.0, -1.0,  0.0,  0.0, -1.0, 10.0,  0.0,  0.973,  0.480,  0.002,
	-0.6,  0.6, -1.0,  0.0,  0.0, -1.0,  2.0,  2.0,  0.973,  0.480,  0.002,
	 0.6,  0.6, -1.0,  0.0,  0.0, -1.0,  8.0,  2.0,  0.973,  0.480,  0.002,
	-0.6, -0.6, -1.0,  0.0,  0.0, -1.0,  2.0,  8.0,  0.973,  0.480,  0.002,
	 0.6, -0.6, -1.0,  0.0,  0.0, -1.0,  8.0,  8.0,  0.973,  0.480,  0.002,
	-1.0, -1.0, -1.0,  0.0,  0.0, -1.0,  0.0, 10.0,  0.973,  0.480,  0.002,
	-0.6, -1.0, -1.0,  0.0,  0.0, -1.0,  2.0, 10.0,  0.973,  0.480,  0.002,
	 0.6, -1.0, -1.0,  0.0,  0.0, -1.0,  8.0, 10.0,  0.973,  0.480,  0.002,
	 1.0, -1.0, -1.0,  0.0,  0.0, -1.0, 10.0, 10.0,  0.973,  0.480,  0.002,
	 1.0,  1.0, -1.0,  1.0,  0.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 1.0,  1.0, -0.6,  1.0,  0.0,  0.0,  2.0,  0.0,  0.897,  0.163,  0.011,
	 1.0,  1.0,  0.6,  1.0,  0.0,  0.0,  8.0,  0.0,  0.897,  0.163,  0.011,
	 1.0,  1.0,  1.0,  1.0,  0.0,  0.0, 10.0,  0.0,  0.897,  0.163,  0.011,
	 1.0,  0.6, -0.6,  1.0,  0.0,  0.0,  2.0,  2.0,  0.897,  0.163,  0.011,
	 1.0,  0.6,  0.6,  1.0,  0.0,  0.0,  8.0,  2.0,  0.897,  0.163,  0.011,
	 1.0, -0.6, -0.6,  1.0,  0.0,  0.0,  2.0,  8.0,  0.897,  0.163,  0.011,
	 1.0, -0.6,  0.6,  1.0,  0.0,  0.0,  8.0,  8.0,  0.897,  0.163,  0.011,
	 1.0, -1.0, -1.0,  1.0,  0.0,  0.0,  0.0, 10.0,  0.897,  0.163,  0.011,
	 1.0, -1.0, -0.6,  1.0,  0.0,  0.0,  2.0, 10.0,  0.897,  0.163,  0.011,
	 1.0, -1.0,  0.6,  1.0,  0.0,  0.0,  8.0, 10.0,  0.897,  0.163,  0.011,
	 1.0, -1.0,  1.0,  1.0,  0.0,  0.0, 10.0, 10.0,  0.897,  0.163,  0.011,
	 1.0,  1.0,  1.0,  0.0,  0.0,  1.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	 0.6,  1.0,  1.0,  0.0,  0.0,  1.0,  2.0,  0.0,  0.612,  0.000,  0.069,
	-0.6,  1.0,  1.0,  0.0,  0.0,  1.0,  8.0,  0.0,  0.612,  0.000,  0.069,
	-1.0,  1.0,  1.0,  0.0,  0.0,  1.0, 10.0,  0.0,  0.612,  0.000,  0.069,
	 0.6,  0.6,  1.0,  0.0,  0.0,  1.0,  2.0,  2.0,  0.612,  0.000,  0.069,
	-0.6,  0.6,  1.0,  0.0,  0.0,  1.0,  8.0,  2.0,  0.612,  0.000,  0.069,
	 0.6, -0.6,  1.0,  0.0,  0.0,  1.0,  2.0,  8.0,  0.612,  0.000,  0.069,
	-0.6, -0.6,  1.0,  0.0,  0.0,  1.0,  8.0,  8.0,  0.612,  0.000,  0.069,
	 1.0, -1.0,  1.0,  0.0,  0.0,  1.0,  0.0, 10.0,  0.612,  0.000,  0.069,
	 0.6, -1.0,  1.0,  0.0,  0.0,  1.0,  2.0, 10.0,  0.612,  0.000,  0.069,
	-0.6, -1.0,  1.0,  0.0,  0.0,  1.0,  8.0, 10.0,  0.612,  0.000,  0.069,
	-1.0, -1.0,  1.0,  0.0,  0.0,  1.0, 10.0, 10.0,  0.612,  0.000,  0.069,
	-1.0,  1.0,  1.0, -1.0,  0.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-1.0,  1.0,  0.6, -1.0,  0.0,  0.0,  2.0,  0.0,  0.127,  0.116,  0.408,
	-1.0,  1.0, -0.6, -1.0,  0.0,  0.0,  8.0,  0.0,  0.127,  0.116,  0.408,
	-1.0,  1.0, -1.0, -1.0,  0.0,  0.0, 10.0,  0.0,  0.127,  0.116,  0.408,
	-1.0,  0.6,  0.6, -1.0,  0.0,  0.0,  2.0,  2.0,  0.127,  0.116,  0.408,
	-1.0,  0.6, -0.6, -1.0,  0.0,  0.0,  8.0,  2.0,  0.127,  0.116,  0.408,
	-1.0, -0.6,  0.6, -1.0,  0.0,  0.0,  2.0,  8.0,  0.127,  0.116,  0.408,
	-1.0, -0.6, -0.6, -1.0,  0.0,  0.0,  8.0,  8.0,  0.127,  0.116,  0.408,
	-1.0, -1.0,  1.0, -1.0,  0.0,  0.0,  0.0, 10.0,  0.127,  0.116,  0.408,
	-1.0, -1.0,  0.6, -1.0,  0.0,  0.0,  2.0, 10.0,  0.127,  0.116,  0.408,
	-1.0, -1.0, -0.6, -1.0,  0.0,  0.0,  8.0, 10.0,  0.127,  0.116,  0.408,
	-1.0, -1.0, -1.0, -1.0,  0.0,  0.0, 10.0, 10.0,  0.127,  0.116,  0.408,
	-1.0,  1.0,  1.0,  0.0,  1.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	-0.6,  1.0,  1.0,  0.0,  1.0,  0.0,  2.0,  0.0,  0.000,  0.254,  0.637,
	 0.6,  1.0,  1.0,  0.0,  1.0,  0.0,  8.0,  0.0,  0.000,  0.254,  0.637,
	 1.0,  1.0,  1.0,  0.0,  1.0,  0.0, 10.0,  0.0,  0.000,  0.254,  0.637,
	-0.6,  1.0,  0.6,  0.0,  1.0,  0.0,  2.0,  2.0,  0.000,  0.254,  0.637,
	 0.6,  1.0,  0.6,  0.0,  1.0,  0.0,  8.0,  2.0,  0.000,  0.254,  0.637,
	-0.6,  1.0, -0.6,  0.0,  1.0,  0.0,  2.0,  8.0,  0.000,  0.254,  0.637,
	 0.6,  1.0, -0.6,  0.0,  1.0,  0.0,  8.0,  8.0,  0.000,  0.254,  0.637,
	-1.0,  1.0, -1.0,  0.0,  1.0,  0.0,  0.0, 10.0,  0.000,  0.254,  0.637,
	-0.6,  1.0, -1.0,  0.0,  1.0,  0.0,  2.0, 10.0,  0.000,  0.254,  0.637,
	 0.6,  1.0, -1.0,  0.0,  1.0,  0.0,  8.0, 10.0,  0.000,  0.254,  0.637,
	 1.0,  1.0, -1.0,  0.0,  1.0,  0.0, 10.0, 10.0,  0.000,  0.254,  0.637,
	-1.0, -1.0, -1.0,  0.0, -1.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	-0.6, -1.0, -1.0,  0.0, -1.0,  0.0,  2.0,  0.0,  0.001,  0.447,  0.067,
	 0.6, -1.0, -1.0,  0.0, -1.0,  0.0,  8.0,  0.0,  0.001,  0.447,  0.067,
	 1.0, -1.0, -1.0,  0.0, -1.0,  0.0, 10.0,  0.0,  0.001,  0.447,  0.067,
	-0.6, -1.0, -0.6,  0.0, -1.0,  0.0,  2.0,  2.0,  0.001,  0.447,  0.067,
	 0.6, -1.0, -0.6,  0.0, -1.0,  0.0,  8.0,  2.0,  0.001,  0.447,  0.067,
	-0.6, -1.0,  0.6,  0.0, -1.0,  0.0,  2.0,  8.0,  0.001,  0.447,  0.067,
	 0.6, -1.0,  0.6,  0.0, -1.0,  0.0,  8.0,  8.0,  0.001,  0.447,  0.067,
	-1.0, -1.0,  1.0,  0.0, -1.0,  0.0,  0.0, 10.0,  0.001,  0.447,  0.067,
	-0.6, -1.0,  1.0,  0.0, -1.0,  0.0,  2.0, 10.0,  0.001,  0.447,  0.067,
	 0.6, -1.0,  1.0,  0.0, -1.0,  0.0,  8.0, 10.0,  0.001,  0.447,  0.067,
	 1.0, -1.0,  1.0,  0.0, -1.0,  0.0, 10.0, 10.0,  0.001,  0.447,  0.067,
	-0.6,  0.6, -1.0,  1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	-0.6,  0.6, -0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	-0.6, -0.6, -0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	-0.6, -0.6, -1.0,  1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	 0.6,  0.6, -0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	 0.6,  0.6, -1.0, -1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	 0.6, -0.6, -1.0, -1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	 0.6, -0.6, -0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	-0.6, -0.6, -1.0,  0.0,  1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	-0.6, -0.6, -0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	 0.6, -0.6, -0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	 0.6, -0.6, -1.0,  0.0,  1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	-0.6,  0.6, -0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	-0.6,  0.6, -1.0,  0.0, -1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	 0.6,  0.6, -1.0,  0.0, -1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	 0.6,  0.6, -0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.973,  0.480,  0.002,
	 1.0,  0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 0.6,  0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 0.6, -0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 1.0, -0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 0.6,  0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 1.0,  0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 1.0, -0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 0.6, -0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 1.0,  0.6,  0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 0.6,  0.6,  0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 0.6,  0.6, -0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 1.0,  0.6, -0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 0.6, -0.6,  0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 1.0, -0.6,  0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 1.0, -0.6, -0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 0.6, -0.6, -0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.897,  0.163,  0.011,
	 0.6,  0.6,  1.0, -1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	 0.6,  0.6,  0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	 0.6, -0.6,  0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	 0.6, -0.6,  1.0, -1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	-0.6,  0.6,  0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	-0.6,  0.6,  1.0,  1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	-0.6, -0.6,  1.0,  1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	-0.6, -0.6,  0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	 0.6, -0.6,  1.0,  0.0,  1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	 0.6, -0.6,  0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	-0.6, -0.6,  0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	-0.6, -0.6,  1.0,  0.0,  1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	 0.6,  0.6,  0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	 0.6,  0.6,  1.0,  0.0, -1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	-0.6,  0.6,  1.0,  0.0, -1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	-0.6,  0.6,  0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.612,  0.000,  0.069,
	-1.0,  0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-0.6,  0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-0.6, -0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-1.0, -0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-0.6,  0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-1.0,  0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-1.0, -0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-0.6, -0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-1.0, -0.6,  0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-0.6, -0.6,  0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-0.6, -0.6, -0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-1.0, -0.6, -0.6,  0.0,  1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-0.6,  0.6,  0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-1.0,  0.6,  0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-1.0,  0.6, -0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-0.6,  0.6, -0.6,  0.0, -1.0,  0.0,  0.0,  0.0,  0.127,  0.116,  0.408,
	-0.6,  1.0,  0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	-0.6,  0.6,  0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	-0.6,  0.6, -0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	-0.6,  1.0, -0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	 0.6,  0.6,  0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	 0.6,  1.0,  0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	 0.6,  1.0, -0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	 0.6,  0.6, -0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	-0.6,  1.0, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	-0.6,  0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	 0.6,  0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	 0.6,  1.0, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	-0.6,  0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	-0.6,  1.0,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	 0.6,  1.0,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	 0.6,  0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.000,  0.254,  0.637,
	-0.6, -0.6,  0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	-0.6, -1.0,  0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	-0.6, -1.0, -0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	-0.6, -0.6, -0.6,  1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	 0.6, -1.0,  0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	 0.6, -0.6,  0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	 0.6, -0.6, -0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	 0.6, -1.0, -0.6, -1.0,  0.0,  0.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	-0.6, -0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	-0.6, -1.0, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	 0.6, -1.0, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	 0.6, -0.6, -0.6,  0.0,  0.0,  1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	-0.6, -1.0,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	-0.6, -0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	 0.6, -0.6,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
	 0.6, -1.0,  0.6,  0.0,  0.0, -1.0,  0.0,  0.0,  0.001,  0.447,  0.067,
}

index_data := [?]u32{
	  0,   1,   9,   9,   8,   0,   1,   2,   5,   5,   4,   1,   6,   7,  10,  10,   9,   6,   2,   3,  11,  11,  10,   2,
	 12,  13,  21,  21,  20,  12,  13,  14,  17,  17,  16,  13,  18,  19,  22,  22,  21,  18,  14,  15,  23,  23,  22,  14,
	 24,  25,  33,  33,  32,  24,  25,  26,  29,  29,  28,  25,  30,  31,  34,  34,  33,  30,  26,  27,  35,  35,  34,  26,
	 36,  37,  45,  45,  44,  36,  37,  38,  41,  41,  40,  37,  42,  43,  46,  46,  45,  42,  38,  39,  47,  47,  46,  38,
	 48,  49,  57,  57,  56,  48,  49,  50,  53,  53,  52,  49,  54,  55,  58,  58,  57,  54,  50,  51,  59,  59,  58,  50,
	 60,  61,  69,  69,  68,  60,  61,  62,  65,  65,  64,  61,  66,  67,  70,  70,  69,  66,  62,  63,  71,  71,  70,  62,
	 72,  73,  74,  74,  75,  72,  76,  77,  78,  78,  79,  76,  80,  81,  82,  82,  83,  80,  84,  85,  86,  86,  87,  84,
	 88,  89,  90,  90,  91,  88,  92,  93,  94,  94,  95,  92,  96,  97,  98,  98,  99,  96, 100, 101, 102, 102, 103, 100,
	104, 105, 106, 106, 107, 104, 108, 109, 110, 110, 111, 108, 112, 113, 114, 114, 115, 112, 116, 117, 118, 118, 119, 116,
	120, 121, 122, 122, 123, 120, 124, 125, 126, 126, 127, 124, 128, 129, 130, 130, 131, 128, 132, 133, 134, 134, 135, 132,
	136, 137, 138, 138, 139, 136, 140, 141, 142, 142, 143, 140, 144, 145, 146, 146, 147, 144, 148, 149, 150, 150, 151, 148,
	152, 153, 154, 154, 155, 152, 156, 157, 158, 158, 159, 156, 160, 161, 162, 162, 163, 160, 164, 165, 166, 166, 167, 164,
}