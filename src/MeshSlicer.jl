module MeshSlicer

using ImmutableArrays

import Base.push!


type Bounds{T<:Number}
    xmax::T
    ymax::T
    zmax::T
    xmin::T
    ymin::T
    zmin::T
end

type Face
    vertices::Array{Vector3{Float64}}
    normal::Vector3{Float64}
    next::Union(Face,Nothing)

    Face(v, n) = new(v, n/norm(n), nothing)
end

type PolygonMesh
    bounds::Bounds
    faces::Union(Face,Nothing)
end

type LineSegment
    start::Vector2{Float64}
    finish::Vector2{Float64}
    normal::Vector3{Float64}
end

type PolygonSlice
    segments::Array{LineSegment}
    layer::Float64
end

################################################################################
#
# PolygonSlice:
#   segments
#   layer
#
# Outer Constructors:
#   PolygonSlice(PolygonMesh, height::Float64
#
################################################################################

function PolygonSlice(mesh::PolygonMesh, height::Float64)

    segmentlist = LineSegment[]

    for face in mesh
        if face.vertices[1].e3 <= height <= face.vertices[3].e3
            seg = LineSegment(face, height)
            if seg != nothing
                push!(segmentlist, seg)
            end
        end
    end

    return PolygonSlice(segmentlist, height)
end

function PolygonSlice(mesh::PolygonMesh, heights::Array{Float64})

    slices = PolygonSlice[]
    for height in heights
        push!(slices, PolygonSlice(LineSegment[],height))
    end

    segmentlist = LineSegment[]

    for face in mesh
        i = 1
        for height in heights
            if face.vertices[1].e3 <= height <= face.vertices[3].e3
                seg = LineSegment(face, height)
                if seg != nothing
                    push!(slices[i].segments, seg)
                end
            end
            i = i + 1
        end
    end

    return slices
end

################################################################################
#
# PolygonMesh:
#   bounds
#   faces
#
# outer constructors:
#   PolygonMesh(m::IOStream)
#       Create a mesh from an STL file IOStream
#
################################################################################

Base.start(m::PolygonMesh) = m.faces
Base.next(m::PolygonMesh, state::Face) = (state, state.next)
Base.done(m::PolygonMesh, state::Face) = false
Base.done(m::PolygonMesh, state::Nothing) = true

PolygonMesh() = PolygonMesh(Bounds(), nothing)

function PolygonMesh(path::String)
    # create a mesh representation 
    file = open(path, "r")

    bounds = Bounds()
    mesh = PolygonMesh()

    # Discover file type
    if endswith(path, ".stl")
        header = ascii(readbytes(file, 5))
        if lowercase(header) == "solid"
            s = :ascii_stl
        else
            readbytes(file, 75) # throw out header
            s = :binary_stl
            read(file, Uint32) # throwout triangle count
        end
    end

    # Construct mesh
    while !eof(file)
        f = Face(file, s)
        if f != nothing
            push!(mesh, f)
            update!(bounds, f)
        end
    end

    mesh.bounds = bounds

    close(file)
    return mesh
end

function rotate!(mesh::PolygonMesh, angle::Float64, axis::Array{Float64}, through::Array{Float64})
    axis = axis/norm(axis) # normalize axis
    a, b, c = through
    u, v, w = axis
    for face in mesh
        for i = 1:3
            x, y, z = face.vertices[i]
            face.vertices[i] = rotate(x, y, z, a, b, c, u, v, w, angle)
        end
        update!(mesh.bounds, face)
    end
end

function rotate(x, y, z, a, b, c, u, v, w, angle)
    # See: http://inside.mines.edu/~gmurray/ArbitraryAxisRotation/#x1-10011
    return Vector3((a*(v^2+w^2)-u*(b*v+c*w-u*x-v*y-w*z))*(1-cos(angle))+x*cos(angle)+(-c*v+b*w-w*y+v*z)*sin(angle),
            (b*(u^2+w^2)-v*(a*u+c*w-u*x-v*y-w*z))*(1-cos(angle))+y*cos(angle)+(c*u-a*w+w*x-u*z)*sin(angle),
            (c*(u^2+v^2)-w*(a*u+b*v-u*x-v*y-w*z))*(1-cos(angle))+z*cos(angle)+(-b*u+a*v-v*x+u*y)*sin(angle))

end

function push!(mesh::PolygonMesh, f::Face)
    if mesh.faces == nothing
        mesh.faces = f
    else
        f.next = mesh.faces
        mesh.faces = f
    end
end
################################################################################
#
# Face:
#   vertices : [[x, y, z], ...]
#       An array of the vertices in the face
#   normal : [x::Float64, y::Float64, x::Float64]
#
#
# outer constructors:
#   Face(f::IOStream, s::Symbol)
#       Pulls a face from an STL file IOStream with type symbol
#       Symbol can be :ascii_stl, :binary_stl
#
################################################################################

function Face(m::IOStream, s::Symbol)
    #  facet normal -1 0 0
    #    outer loop
    #      vertex 0 0 10
    #      vertex 0 10 10
    #      vertex 0 0 0
    #    endloop
    #  endfacet
    if s == :ascii_stl
        line = split(lowercase(readline(m)))
        if line[1] == "facet"
            normal = Vector3(float64(line[3:5]))
            readline(m) # Throw away outerloop
            vertices = [Vector3(float64(split(readline(m))[2:4])) for i = 1:3]
            return Face(vertices, normal)
        end

    elseif s == :binary_stl
        normal = Vector3([float64(read(m, Float32)) for i = 1:3])
        vertices = [Vector3([float64(read(m, Float32)) for i = 1:3]) for j = 1:3]
        read(m, Uint16) # throwout attribute
        return Face(vertices, normal)
    end

    # If we can't find anything, return nothing
    return nothing
end

function (==)(a::Face, b::Face)
    return (a.vertices == b.vertices &&
            a.normal == b.normal)
end

################################################################################
#
# LineSegment:
#   start : [x::Float64, y::Float64]
#   finish : [x::Float64, y::Float64]
#   slope :
#       slope in slice plane, computed automatically by inner constructor
#
# outer constructors:
#   LineSegment(f::Face, z::Number, normal)
#   LineSegment(p0, p1, p2, z::Number, normal)
#       p0, p1, p2 are expected to be Arrays of size 3 containing numbers
#
################################################################################

function LineSegment(f::Face, z::Float64)

    p0 = f.vertices[1]
    p1 = f.vertices[2]
    p2 = f.vertices[3]

    if p0.e3 < z && p1.e3 >= z && p2.e3 >= z
        return LineSegment(p0, p2, p1, z, f.normal)
    elseif p0.e3 > z && p1.e3 < z && p2.e3 < z
        return LineSegment(p0, p1, p2, z, f.normal)
    elseif p1.e3 < z && p0.e3 >= z && p2.e3 >= z
        return LineSegment(p1, p0, p2, z, f.normal)
    elseif p1.e3 > z && p0.e3 < z && p2.e3 < z
        return LineSegment(p1, p2, p0, z, f.normal)
    elseif p2.e3 < z && p1.e3 >= z && p0.e3 >= z
        return LineSegment(p2, p1, p0, z, f.normal)
    elseif p2.e3 > z && p1.e3 < z && p0.e3 < z
        return LineSegment(p2, p0, p1, z, f.normal)
    else
        return nothing
    end

end

function LineSegment(p0::Vector3, p1::Vector3, p2::Vector3, z::Float64, normal::Vector3)
    start = Vector2(p0.e1 + (p1.e1 - p0.e1) * (z - p0.e3) / (p1.e3 - p0.e3),
                    p0.e2 + (p1.e2 - p0.e2) * (z - p0.e3) / (p1.e3 - p0.e3))
    finish = Vector2(p0.e1 + (p2.e1 - p0.e1) * (z - p0.e3) / (p2.e3 - p0.e3),
                     p0.e2 + (p2.e2 - p0.e2) * (z - p0.e3) / (p2.e3 - p0.e3))
    return LineSegment(start, finish, normal);
end


function (==)(a::LineSegment, b::LineSegment)
    return (a.start == b.start &&
            a.finish == b.finish)
end

################################################################################
#
# Bounds:
#   xmax
#   ymax
#   zmax
#   xmin
#   ymin
#   zmin
#
# Methods:
#   update!(Bounds, Face)
#       update the bounds against a face
#
################################################################################

function Bounds()
    return Bounds{Float64}(-Inf,-Inf,-Inf,Inf,Inf,Inf)
end

function update!(box::Bounds, face::Face)
    xmin, xmax = extrema([face.vertices[i].e1 for i = 1:3])
    ymin, ymax = extrema([face.vertices[i].e2 for i = 1:3])
    zmin, zmax = extrema([face.vertices[i].e3 for i = 1:3])

    box.xmin = min(xmin, box.xmin)
    box.ymin = min(ymin, box.ymin)
    box.zmin = min(zmin, box.zmin)
    box.xmax = max(xmax, box.xmax)
    box.ymax = max(ymax, box.ymax)
    box.zmax = max(zmax, box.zmax)
end

function (==)(a::Bounds, b::Bounds)
    return (a.xmax == b.xmax &&
            a.ymax == b.ymax &&
            a.zmax == b.zmax &&
            a.xmin == b.xmin &&
            a.ymin == b.ymin &&
            a.zmin == b.zmin)
end

export Bounds, Face, PolygonMesh, LineSegment, PolygonSlice, update!, rotate!, rotate
end # module
