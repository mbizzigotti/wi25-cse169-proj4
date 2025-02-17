'use strict'

const app = document.getElementById("app");
const gl  = app.getContext("webgl2");

// Imma blue ba da!
gl.clearColor(0.0, 0.0, 0.2, 1.0);
gl.clear(gl.COLOR_BUFFER_BIT);

let c_floats = null;

// Convert C float[] to Javascript Float32Array
function c_float_array(address, size) {
    const base = address >> 2; // want an index (float = 4 bytes)
    return c_floats.slice(base, base + size);
}

const shaders = {};
const uniforms = {
    mat4_ViewProj: null,
}
const scene = {
    skybox: {
        shader: "skybox",
        uniforms: ["mat4_ViewProj"],
        draw: () => gl.drawArrays(gl.TRIANGLES, 0, 36),
    },
    floor: {
        shader: "floor",
        uniforms: ["mat4_ViewProj"],
        draw: () => {
            gl.cullFace(gl.BACK);
            gl.enable(gl.BLEND);
            gl.disable(gl.DEPTH_TEST);
            gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
            gl.drawArrays(gl.TRIANGLES, 0, 6);
            gl.enable(gl.DEPTH_TEST);
        },
    },
    cloth: {
        shader: "cloth",
        uniforms: ["mat4_ViewProj"],
        buffers: {
            position : gl.createBuffer(),
            color    : gl.createBuffer(),
            normal   : gl.createBuffer(),
        },
        index: load_quad_index_buffer((40-1)*(30-1)),
        draw: (count) => {
            gl.disable(gl.CULL_FACE)
            gl.disable(gl.BLEND);
            gl.drawElements(gl.TRIANGLES, count, gl.UNSIGNED_SHORT, 0);
        },
    },
    ball: {
        shader: "cloth",
        uniforms: ["mat4_ViewProj"],
        buffers: load_sphere_vertex_buffer(0.48, 50, 50),
        index: load_sphere_index_buffer(50, 50),
        draw: (count) => {
            gl.drawElements(gl.TRIANGLES, count, gl.UNSIGNED_SHORT, 0);
        },
    }
}

const upload_cloth_vertices = (count, positions, colors, normals) => {
    count = count * 3;

    gl.bindBuffer(gl.ARRAY_BUFFER, scene.cloth.buffers.position);
    gl.bufferData(gl.ARRAY_BUFFER, c_float_array(positions, count), gl.DYNAMIC_DRAW);

    gl.bindBuffer(gl.ARRAY_BUFFER, scene.cloth.buffers.color);
    gl.bufferData(gl.ARRAY_BUFFER, c_float_array(colors, count), gl.DYNAMIC_DRAW);

    gl.bindBuffer(gl.ARRAY_BUFFER, scene.cloth.buffers.normal);
    gl.bufferData(gl.ARRAY_BUFFER, c_float_array(normals, count), gl.DYNAMIC_DRAW);
}

const set_view_projection = (matrix) => {
    uniforms.mat4_ViewProj = c_float_array(matrix, 16);
}

const draw_scene = () => {
    for (const [key, object] of Object.entries(scene)) {
        const shader = shaders[object.shader];
        gl.useProgram(shader.program);
        for (const uniform_name of object.uniforms) {
            const location = gl.getUniformLocation(shader.program, uniform_name);
            // TODO: call correct function based on prefix e.g. "mat4_" => Matrix4fv
            gl.uniformMatrix4fv(location, false, uniforms[uniform_name]);
        }
        // NOTE: At this point it is probably time to let the wasm handle the vertex buffers themselves,
        //       and not have this garbage here. Or have some kind of mesh abstraction
        if (Object.hasOwn(object, "buffers")) {
            gl.bindBuffer(gl.ARRAY_BUFFER, object.buffers.position);
            gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
            gl.enableVertexAttribArray(0);

            gl.bindBuffer(gl.ARRAY_BUFFER, object.buffers.color);
            gl.vertexAttribPointer(1, 3, gl.FLOAT, false, 0, 0);
            gl.enableVertexAttribArray(1);

            gl.bindBuffer(gl.ARRAY_BUFFER, object.buffers.normal);
            gl.vertexAttribPointer(2, 3, gl.FLOAT, false, 0, 0);
            gl.enableVertexAttribArray(2);

            gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, object.index.buffer);
            object.draw(object.index.count);    
        }
        else object.draw();
    }
}

WebAssembly.instantiateStreaming(fetch('bin/lib.wasm'), {
    env: {
        set_view_projection,
        sinf: (x) => Math.sin(x), // TODO: this needed?
        cosf: (x) => Math.cos(x), // TODO: this needed?
        get_aspect: () => (app.clientWidth / app.clientHeight), // TODO: remove
        draw_scene,
        upload_cloth_vertices,
    }
}).then(async (wasm) => {
    const c = wasm.instance.exports;
    c_floats = new Float32Array(c.memory.buffer);

    const on_resize = () => {
        app.width  = window.innerWidth;
        app.height = window.innerHeight;
        gl.viewport(0, 0, app.width, app.height);
        console.info("Resized: ", app.width, "x", app.height);
        // TODO: call on_resize callback from Odin
    }
    window.addEventListener("resize", on_resize);
    on_resize();

    const elem_shaders = document.getElementsByClassName("shader");
    for (const elem_shader of elem_shaders) {
        const info = elem_shader.type.split('/');
        const name = info[0];
        const type = info[1];
        if (shaders[name] == null)
            shaders[name] = {};
        shaders[name][type] = elem_shader.textContent;
    }
    compile_shaders(shaders);

    gl.enable(gl.DEPTH_TEST);

    c.setup();

    document.addEventListener('mousedown', (e) => {
        c.on_mouse_down();
    });
    document.addEventListener('mouseup', (e) => {
        c.on_mouse_up();
    });
    document.addEventListener('mouseleave', (e) => {
        c.on_mouse_up(); // HACK, probably want a seperate event?
    });
    document.addEventListener('mousemove', (e) => {
        c.on_mouse_move(e.clientX, e.clientY);
    });
    document.addEventListener('keydown', (e) => {
        c.on_key_down(e.key.charCodeAt(0));
    });

    let prev = null;
    function loop(timestamp) {
        if (prev === undefined) prev = timestamp;
        const dt = (timestamp - prev)*0.001;
        // Wait, if we are not clearing, how does the depth buffer get cleared???
        // 🪄 🐇
        c.update(dt);
        document.getElementById("FPS").textContent = `FPS: ${(1.0 / dt).toFixed(1)}`;
        prev = timestamp;
        window.requestAnimationFrame(loop);
    }
    window.requestAnimationFrame(loop);
})

function compile_shaders(shaders) {
    console.log(shaders);
    for (const [key,source] of Object.entries(shaders)) {
        shaders[key].program = create_shader_program(source.vertex, source.fragment)
    }
}

function create_shader_program(vsSource, fsSource) {
    const vertexShader   = load_shader(gl.VERTEX_SHADER,   vsSource);
    const fragmentShader = load_shader(gl.FRAGMENT_SHADER, fsSource);
  
    const shaderProgram = gl.createProgram();
    gl.attachShader(shaderProgram, vertexShader);
    gl.attachShader(shaderProgram, fragmentShader);
    gl.linkProgram(shaderProgram);
  
    if (!gl.getProgramParameter(shaderProgram, gl.LINK_STATUS)) {
        console.error(`Unable to initialize the shader program: ${gl.getProgramInfoLog( shaderProgram, )}`);
        return null;
    }
  
    return shaderProgram;
}

function load_shader(type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, `#version 300 es\n${source}`);
    gl.compileShader(shader);

    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        console.error(`An error occurred compiling the shaders: ${gl.getShaderInfoLog(shader)}`);
        gl.deleteShader(shader);
        return null;
    }

    return shader;
}

function load_quad_index_buffer(quad_count) {
    const buffer = gl.createBuffer();
    const data = new Uint16Array(quad_count * 6);

    const w = 40, h = 30;
    let i = 0
    for (let y = 0; y<(h-1); ++y) {
        for (let x = 0; x<(w-1); ++x) {
            const base = y * w + x;
            data[i++] = base + 0;
            data[i++] = base + 1;
            data[i++] = base + w;
            data[i++] = base + 1;
            data[i++] = base + w + 1;
            data[i++] = base + w;
        }
    }

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, data, gl.STATIC_DRAW);

    return { count: data.length, buffer: buffer };
}

function load_sphere_vertex_buffer(radius, latitudeBands, longitudeBands) {
    const vertices = [];
    const normals  = [];
    const colors   = [];
    
    for (let lat = 0; lat <= latitudeBands; lat++) {
        const theta = (lat * Math.PI) / latitudeBands;
        const sinTheta = Math.sin(theta);
        const cosTheta = Math.cos(theta);
        
        for (let lon = 0; lon <= longitudeBands; lon++) {
            const phi = (lon * 2 * Math.PI) / longitudeBands;
            const sinPhi = Math.sin(phi);
            const cosPhi = Math.cos(phi);
            
            const x = cosPhi * sinTheta;
            const y = cosTheta;
            const z = sinPhi * sinTheta;
            
            vertices.push(radius * x, radius * y, radius * z);
            normals.push(-x, -y, -z);
            colors.push(0.5,0.5,0.5);
        }
    }
    
    const vertexBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(vertices), gl.STATIC_DRAW);

    const colorBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, colorBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(colors), gl.STATIC_DRAW);

    const normalBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, normalBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(normals), gl.STATIC_DRAW);
    
    return { position: vertexBuffer, color: colorBuffer, normal: normalBuffer };
}

function load_sphere_index_buffer(latitudeBands, longitudeBands) {
    const indices = [];
    
    for (let lat = 0; lat < latitudeBands; lat++) {
        for (let lon = 0; lon < longitudeBands; lon++) {
            const first = (lat * (longitudeBands + 1)) + lon;
            const second = first + longitudeBands + 1;
            
            indices.push(first, second, first + 1);
            indices.push(second, second + 1, first + 1);
        }
    }
    
    const indexBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array(indices), gl.STATIC_DRAW);
    
    return { count: indices.length, buffer: indexBuffer };
}
