module MeshSlicer

type PolygonSlice
    segments
    layer
end

type Bounds
    xmax::Float64
    ymax::Float64
    zmax::Float64
    xmin::Float64
    ymin::Float64
    zmin::Float64
end

type Face
    vertices::Array{Array}
    normal::Array{Float64}
end

type PolygonMesh
    bounds::Bounds
    faces::Array{Face}
end

type LineSegment
    start::Array{Float64}
    finish::Array{Float64}
    slope::Float64
    normal::Array{Float64}

    LineSegment(x,y) = new(x,y,(x[1]-y[1])/(x[2]-y[2])) # compute slope
end


function slice(path::String, thickness)
    file = open(path, "r")

    mesh = PolygonMesh(file, :ascii_stl)

    close(file)

    startZ = mesh.bounds.zmin

    #We can only print an integer number of layers
    layercount = round((mesh.bounds.zmax - mesh.bounds.zmin)/thickness)

    #Adjust sliceheight
    sliceheight = (mesh.bounds.zmax - mesh.bounds.zmin)/layercount

    layers = [mesh.bounds.zmin:sliceheight:mesh.bounds.zmax]

    segmentlist = Array(PolygonSlice,convert(Int64,layercount))

    for i = 1:layercount
        segmentlist[i] = PolygonSlice(LineSegment[],layers[i])
    end

    #println(segmentlist)
    for face in mesh.faces

        initialSlice = convert(Int64, floor((face.vertices[1][3] - mesh.bounds.zmin)/sliceheight))
        finalSlice = convert(Int64, floor((face.vertices[3][3] - mesh.bounds.zmin)/sliceheight))

        locallayer = layers[initialSlice+1:finalSlice]

        index = initialSlice + 1
        for layer in locallayer
            seg = LineSegment(face, layer)
            if seg != Nothing
                push!(segmentlist[index].segments, seg)
            end
            index = index + 1
        end
    end
    return segmentlist
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

function PolygonMesh(m::IOStream, s::Symbol)
    # create a mesh representation 

    faces = Face[]
    bounds = Bounds(0,0,0,Inf,Inf,Inf)

    if s == :ascii_stl
        while !eof(m)
            f = Face(m, s)
            if f != Nothing
                push!(faces, f)
                update!(bounds, f)
            end
        end
    end

    return PolygonMesh(bounds, faces)
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
#   Face(f::IOStream)
#       Pulls a face from an STL file IOStream
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
        vertices = [zeros(3) for i = 1:3]
        normal = zeros(3)
        line = split(lowercase(readline(m)))
        if line[1] == "facet"
            normal = float64(line[3:5])
            normal = normal/norm(normal) # make sure normal is actually normal
            readline(m) # Throw away outerloop
            for i = 1:3 # Get vertices
                line = split(lowercase(readline(m)))
                vertices[i] = float64(line[2:4])
            end
            sort!(vertices, by=x->x[3]) # Sort by 3rd index.
            return Face(vertices, normal)
        else
            return Nothing
        end
    end
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
#   LineSegment(f::Face, z::Number)
#   LineSegment(p0, p1, p2, z::Number)
#       p0, p1, p2 are expected to be Arrays of size 3 containing numbers
#
################################################################################

function LineSegment(f::Face, z)

    p0 = f.vertices[1]
    p1 = f.vertices[2]
    p2 = f.vertices[3]

    if p0[3] < z && p1[3] >= z && p2[3] >= z
        return LineSegment(p0, p2, p1, z)
    elseif p0[3] > z && p1[3] < z && p2[3] < z
        return LineSegment(p0, p1, p2, z)
    elseif p1[3] < z && p0[3] >= z && p2[3] >= z
        return LineSegment(p1, p0, p2, z)
    elseif p1[3] > z && p0[3] < z && p2[3] < z
        return LineSegment(p1, p2, p0, z)
    elseif p2[3] < z && p1[3] >= z && p0[3] >= z
        return LineSegment(p2, p1, p0, z)
    elseif p2[3] > z && p1[3] < z && p0[3] < z
        return LineSegment(p2, p0, p1, z)
    else
        return Nothing
    end

end

function LineSegment(p0::Array, p1::Array, p2::Array, z)
    start = zeros(2)
    finish = zeros(2)
    start[1] = p0[1] + (p1[1] - p0[1]) * (z - p0[3]) / (p1[3] - p0[3]);
    start[2] = p0[2] + (p1[2] - p0[2]) * (z - p0[3]) / (p1[3] - p0[3]);
    finish[1] = p0[1] + (p2[1] - p0[1]) * (z - p0[3]) / (p2[3] - p0[3]);
    finish[2] = p0[2] + (p2[2] - p0[2]) * (z - p0[3]) / (p2[3] - p0[3]);
    return LineSegment(start, finish);
end


function (==)(a::LineSegment, b::LineSegment)
    return (a.start == b.start &&
            a.finish == b.finish &&
            a.slope == b.slope)
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
################################################################################


function update!(box::Bounds, face::Face)
    x = sort(face.vertices, by=x->x[1]) # Sort by x
    y = sort(face.vertices, by=x->x[2]) # Sort by y

    box.xmin = min(x[1][1], box.xmin)
    box.ymin = min(y[1][2], box.ymin)
    box.zmin = min(face.vertices[1][3], box.zmin)
    box.xmax = max(x[3][1], box.xmax)
    box.ymax = max(y[3][2], box.ymax)
    box.zmax = max(face.vertices[3][3], box.zmax)
end

function (==)(a::Bounds, b::Bounds)
    return (a.xmax == b.xmax &&
            a.ymax == b.ymax &&
            a.zmax == b.zmax &&
            a.xmin == b.xmin &&
            a.ymin == b.ymin &&
            a.zmin == b.zmin)
end

end # module
