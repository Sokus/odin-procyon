package graphics

import win "core:sys/windows"
import glm "core:math/linalg/glsl"
import "core:strings"
import "core:fmt"

import D3D11 "vendor:directx/d3d11"
import D3D "vendor:directx/d3d_compiler"

ShaderConstantProjection :: struct #align 16 {
	matrix_projection: glm.mat4,
}

ShaderConstantView :: struct #align 16 {
	matrix_view: glm.mat4,
}

ShaderConstantModel :: struct #align 16 {
	matrix_model: glm.mat4,
}

ShaderConstantLight :: struct #align 16 {
	light_vector: glm.vec3,
}

shader_constants := map[typeid](^D3D11.IBuffer){
	ShaderConstantProjection = nil,
	ShaderConstantView = nil,
	ShaderConstantModel = nil,
	ShaderConstantLight = nil,
}

initialize_constant_buffers :: proc() {
	for constant_buffer_type in shader_constants {
		constant_buffer_info := type_info_of(constant_buffer_type)
		constant_buffer_desc := D3D11.BUFFER_DESC{
			ByteWidth      = u32(constant_buffer_info.size),
			Usage          = .DYNAMIC,
			BindFlags      = {.CONSTANT_BUFFER},
			CPUAccessFlags = {.WRITE},
		}
		state.device->CreateBuffer(&constant_buffer_desc, nil, &shader_constants[constant_buffer_type])
	}
}

shader_constant_begin_map :: proc($T: typeid) -> (pointer: ^T) {
	resource := shader_constants[T]
	mapped_subresource: D3D11.MAPPED_SUBRESOURCE
	state.device_context->Map(resource, 0, .WRITE_DISCARD, {}, &mapped_subresource)
	pointer = (^T)(mapped_subresource.pData)
	return
}

shader_constant_end_map :: proc($T: typeid) {
	resource := shader_constants[T]
	state.device_context->Unmap(resource, 0)
}

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