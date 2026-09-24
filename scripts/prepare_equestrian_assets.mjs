// Expand the source GLB's quantized vectors to core glTF floats for Godot.
// Vertex positions, normals, node transforms, and materials are preserved.
import fs from 'node:fs'
import path from 'node:path'
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'

const directory = 'godot/assets/equestrian'
const source = fs.readFileSync(path.join(directory, 'source/arena_rail.glb'))
const jsonSize = source.readUInt32LE(12)
const document = JSON.parse(source.subarray(20, 20 + jsonSize))
const binary = source.subarray(28 + jsonSize)
assert.equal(document.buffers.length, 1)
assert.equal(document.images?.length ?? 0, 0)
const chunks = [], views = []
let offset = 0
for (const accessor of document.accessors) {
  assert.equal(accessor.componentType, 5122)
  assert.equal(accessor.type, 'VEC3')
  assert.equal(accessor.normalized, true)
  assert.equal(accessor.sparse, undefined)
  const view = document.bufferViews[accessor.bufferView]
  const expanded = Buffer.alloc(accessor.count * 12)
  const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity]
  for (let i = 0; i < accessor.count; i++) {
    for (let component = 0; component < 3; component++) {
      const at = (view.byteOffset ?? 0) + (accessor.byteOffset ?? 0) + i * (view.byteStride ?? 6) + component * 2
      const value = Math.max(binary.readInt16LE(at) / 32767, -1)
      expanded.writeFloatLE(value, i * 12 + component * 4)
      min[component] = Math.min(min[component], value)
      max[component] = Math.max(max[component], value)
    }
  }
  accessor.bufferView = views.length
  accessor.byteOffset = 0
  accessor.componentType = 5126
  delete accessor.normalized
  if (accessor.min) accessor.min = min
  if (accessor.max) accessor.max = max
  views.push({buffer: 0, byteOffset: offset, byteLength: expanded.length, target: 34962})
  chunks.push(expanded)
  offset += expanded.length
}
document.bufferViews = views
document.buffers = [{byteLength: offset}]
for (const key of ['extensionsUsed', 'extensionsRequired']) {
  document[key] = document[key].filter(name => name !== 'KHR_mesh_quantization')
  if (!document[key].length) delete document[key]
}
const json = Buffer.from(JSON.stringify(document))
const jsonChunk = Buffer.alloc(Math.ceil(json.length / 4) * 4, 0x20)
json.copy(jsonChunk)
const header = Buffer.alloc(20)
header.writeUInt32LE(0x46546c67, 0)
header.writeUInt32LE(2, 4)
header.writeUInt32LE(28 + jsonChunk.length + offset, 8)
header.writeUInt32LE(jsonChunk.length, 12)
header.writeUInt32LE(0x4e4f534a, 16)
const binaryHeader = Buffer.alloc(8)
binaryHeader.writeUInt32LE(offset, 0)
binaryHeader.writeUInt32LE(0x004e4942, 4)
const result = Buffer.concat([header, jsonChunk, binaryHeader, ...chunks])
fs.writeFileSync(path.join(directory, 'arena_rail.glb'), result)
const manifestPath = path.join(directory, 'manifest.json')
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8').replace(/^\uFEFF/, ''))
manifest.sha256 = createHash('sha256').update(source).digest('hex')
manifest.convertedSha256 = createHash('sha256').update(result).digest('hex')
manifest.conversion = 'KHR_mesh_quantization vectors expanded to Float32; original geometry, materials and transforms retained.'
fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n')
console.log(`Prepared ${result.length} bytes of Godot-compatible railing geometry`)
