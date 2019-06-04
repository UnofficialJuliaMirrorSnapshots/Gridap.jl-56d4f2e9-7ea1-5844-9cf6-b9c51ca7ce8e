include("MultiCellArrays.jl")

module MultiCellMaps

using Gridap
using Gridap.CellMaps
using Gridap.Geometry
using Gridap.CellQuadratures
using ..MultiCellArrays

export MultiCellMap
import Gridap.CellIntegration: integrate
import Base: +, -

struct MultiCellMap{N}
  blocks::Vector{<:CellMap}
  fieldids::Vector{NTuple{N,Int}}
end

function integrate(
  mcm::MultiCellMap,
  trian::Triangulation{Z},
  quad::CellQuadrature{Z}) where Z

  blocks = [ integrate(b,trian,quad) for b in mcm.blocks ]

  MultiCellArray(blocks,mcm.fieldids)

end

function (+)(a::MultiCellMap{N},b::MultiCellMap{N}) where N
  blocks = CellMap[]
  append!(blocks,a.blocks)
  append!(blocks,b.blocks)
  fieldids = NTuple{N,Int}[]
  append!(fieldids,a.fieldids)
  append!(fieldids,b.fieldids)
  MultiCellMap(blocks,fieldids)
end

function (-)(a::MultiCellMap{N},b::MultiCellMap{N}) where N
  blocks = CellMap[]
  append!(blocks,a.blocks)
  append!(blocks,[ -k for k in b.blocks])
  fieldids = NTuple{N,Int}[]
  append!(fieldids,a.fieldids)
  append!(fieldids,b.fieldids)
  MultiCellMap(blocks,fieldids)
end

end # module MultiCellMaps