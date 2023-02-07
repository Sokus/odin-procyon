package graphics

import glm "core:math/linalg/glsl"

import D3D11 "vendor:directx/d3d11"

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
	state.device->CreateBuffer(&vertex_buffer_desc, &subresource_data, &mesh.position_buffer)

	assert(len(mesh.texcoords) > 0)
	texcoords_size := cast(u32)(len(mesh.texcoords) * size_of(f32))
	vertex_buffer_desc.ByteWidth = texcoords_size
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.texcoords[0], SysMemPitch = texcoords_size }
	state.device->CreateBuffer(&vertex_buffer_desc, &subresource_data, &mesh.texcoord_buffer)

	assert(len(mesh.normals) > 0)
	normals_size := cast(u32)(len(mesh.normals) * size_of(f32))
	vertex_buffer_desc.ByteWidth = normals_size
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.normals[0], SysMemPitch = normals_size }
	state.device->CreateBuffer(&vertex_buffer_desc, &subresource_data, &mesh.normal_buffer)

	if len(mesh.colors) == 0 {
		mesh.default_color = true
		colors := []u32{ 0xff0000ff }
		mesh.colors = make([]u32, len(colors))
		copy_slice(mesh.colors, colors)
	}

	colors_size := cast(u32)(len(mesh.colors) * size_of(f32))
	vertex_buffer_desc.ByteWidth = colors_size
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.colors[0], SysMemPitch = colors_size }
	state.device->CreateBuffer(&vertex_buffer_desc, &subresource_data, &mesh.color_buffer)

	indices_size := cast(u32)(len(mesh.indices) * size_of(u32))
	index_buffer_desc := D3D11.BUFFER_DESC{
		Usage = .IMMUTABLE,
		BindFlags = {.INDEX_BUFFER},
		ByteWidth = indices_size,
	}
	subresource_data = D3D11.SUBRESOURCE_DATA{ pSysMem = &mesh.indices[0], SysMemPitch = indices_size }
	state.device->CreateBuffer(&index_buffer_desc, &subresource_data, &mesh.index_buffer)
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

	constant_model := shader_constant_begin_map(ShaderConstantModel)
	constant_model.matrix_model = translate * rotate_z * rotate_y * rotate_x
	shader_constant_end_map(ShaderConstantModel)

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

    state.device_context->IASetPrimitiveTopology(.TRIANGLELIST)
	state.device_context->IASetInputLayout(state.input_layouts[int(mesh.default_color)])
	state.device_context->IASetVertexBuffers(0, len(vertex_buffers), &vertex_buffers[0], &vertex_buffer_strides[0], &vertex_buffer_offsets[0])
	state.device_context->IASetIndexBuffer(mesh.index_buffer, .R32_UINT, 0)

	state.device_context->DrawIndexed(u32(len(mesh.indices)), 0, 0)
}