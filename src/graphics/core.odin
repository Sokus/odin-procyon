package graphics

import "core:fmt"
import win "core:sys/windows"
import glm "core:math/linalg/glsl"
import "core:strings"

import DXGI "vendor:directx/dxgi"
import D3D11 "vendor:directx/d3d11"
import D3D "vendor:directx/d3d_compiler"
import "core:runtime"

State :: struct {
    device: ^D3D11.IDevice,
    device_context: ^D3D11.IDeviceContext,
	swapchain: ^DXGI.ISwapChain1,
	framebuffer_view: ^D3D11.IRenderTargetView,
	depth_buffer_view: ^D3D11.IDepthStencilView,

	rasterizer_state: ^D3D11.IRasterizerState,
	sampler_state: ^D3D11.ISamplerState,
	depth_stencil_state: ^D3D11.IDepthStencilState,

	vs_blob, ps_blob: ^D3D11.IBlob,
	vertex_shader: ^D3D11.IVertexShader,
	pixel_shader: ^D3D11.IPixelShader,
	input_layouts: [2]^D3D11.IInputLayout,
}

state: State

initialize :: proc(hwnd: win.HWND) {
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

	base_device_context->QueryInterface(D3D11.IDeviceContext_UUID, (^rawptr)(&state.device_context))

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

	result = dxgi_factory->CreateSwapChainForHwnd(state.device, hwnd, &swapchain_desc, nil, nil, &state.swapchain)
	if !win.SUCCEEDED(result) {
		fmt.printf("DXGI: Failed to create Swapchain (0x%x)\n", u32(result))
		return
	}

    create_swapchain_resources()

	///////////////////////////////////////////////////////////////////////////////////////////////

	state.vertex_shader, state.vs_blob = create_vertex_shader(state.device, "assets/shader.hlsl")
	assert(state.vs_blob != nil)

	input_element_desc := [?]D3D11.INPUT_ELEMENT_DESC{
		{ "POS", 0, .R32G32B32_FLOAT, 0,                            0, .VERTEX_DATA, 0 },
		{ "NOR", 0, .R32G32B32_FLOAT, 1, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
		{ "TEX", 0, .R32G32_FLOAT,    2, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
		{ "COL", 0, .R8G8B8A8_UNORM, 3, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
	}
	state.device->CreateInputLayout(
		&input_element_desc[0],
		len(input_element_desc),
		state.vs_blob->GetBufferPointer(),
		state.vs_blob->GetBufferSize(),
		&state.input_layouts[0],
	)

	input_element_desc[3].InputSlotClass = .INSTANCE_DATA
	state.device->CreateInputLayout(
		&input_element_desc[0],
		len(input_element_desc),
		state.vs_blob->GetBufferPointer(),
		state.vs_blob->GetBufferSize(),
		&state.input_layouts[1],
	)

	state.pixel_shader, state.ps_blob = create_pixel_shader(state.device, "assets/shader.hlsl")

	///////////////////////////////////////////////////////////////////////////////////////////////

	rasterizer_desc := D3D11.RASTERIZER_DESC{
		FillMode = .SOLID,
		CullMode = .BACK,
	}
	result = state.device->CreateRasterizerState(&rasterizer_desc, &state.rasterizer_state)

	sampler_desc := D3D11.SAMPLER_DESC{
		Filter         = .MIN_MAG_MIP_POINT,
		AddressU       = .WRAP,
		AddressV       = .WRAP,
		AddressW       = .WRAP,
		ComparisonFunc = .NEVER,
	}
	state.device->CreateSamplerState(&sampler_desc, &state.sampler_state)

	depth_stencil_desc := D3D11.DEPTH_STENCIL_DESC{
		DepthEnable    = true,
		DepthWriteMask = .ALL,
		DepthFunc      = .LESS,
	}
	state.device->CreateDepthStencilState(&depth_stencil_desc, &state.depth_stencil_state)

	///////////////////////////////////////////////////////////////////////////////////////////////

	initialize_constant_buffers()
}

shutdown :: proc() {
    state.swapchain->Release()
}

create_swapchain_resources :: proc() {
    result : DXGI.HRESULT

    framebuffer: ^D3D11.ITexture2D
	result = state.swapchain->GetBuffer(0, D3D11.ITexture2D_UUID, (^rawptr)(&framebuffer))
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to get Framebuffer form swapchain (0x%x)\n", u32(result))
		return;
	}
	defer framebuffer->Release()

	result = state.device->CreateRenderTargetView(framebuffer, nil, &state.framebuffer_view)
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to create Render Target View (0x%x)\n", u32(result))
		return
	}

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

	result = state.device->CreateDepthStencilView(depth_buffer, nil, &state.depth_buffer_view)
	if !win.SUCCEEDED(result) {
		fmt.printf("D3D11: Failed to create Depth Stencil View (0x%x)\n", u32(result))
		return
	}
}

destroy_swapchain_resources :: proc() {
    state.device_context->OMSetRenderTargets(0, nil, nil)

    if state.framebuffer_view != nil {
        state.framebuffer_view->Release()
        state.framebuffer_view = nil
    }

    if state.depth_buffer_view != nil {
        state.depth_buffer_view->Release()
        state.depth_buffer_view = nil
    }
}

set_viewport :: proc(width, height: int) {
	viewport := D3D11.VIEWPORT{
		0, 0,
		f32(width), f32(height),
		0, 1,
	}

	w := viewport.Width / viewport.Height
	h := f32(1)
	n := f32(1)
	f := f32(9)

	constant_projection := shader_constant_begin_map(ShaderConstantProjection)
	constant_projection.matrix_projection = {
		2 * n / w, 0,         0,           0,
		0,         2 * n / h, 0,           0,
		0,         0,         f / (f - n), n * f / (n - f),
		0,         0,         1,           0,
	}
	shader_constant_end_map(ShaderConstantProjection)

	state.device_context->RSSetViewports(1, &viewport)
}

on_resize :: proc (new_width, new_height: int) {
    state.device_context->Flush()

    destroy_swapchain_resources()

    state.swapchain->ResizeBuffers(0, u32(new_width), u32(new_height), .UNKNOWN, 0)

    create_swapchain_resources()
}