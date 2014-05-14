module MeshSlicer

#Setup types
type Face
    vertices::Array
    normal::Array{Float64}
    heights::Array{Int64} # indices of min, middle, max z height
end

type Bounds
    maxX::Float64
    maxY::Float64
    maxZ::Float64
    minX::Float64
    minY::Float64
    minZ::Float64
end

type Volume
    bounds::Bounds
    faces::Array{Face}
end

function sliceSTL(path::String)
    file = open(path, "r")
    
    volume = getvolume(file)
    
    println(volume)
end

function getvolume(m::IOStream)
    # create a volume representation 
    
    faces = Face[]
    bounds = Bounds(0,0,0,0,0,0)
    
    while !eof(m)
        f = getface(m)
        if f != Nothing
            push!(faces, f)
            updatebounds!(bounds, f)
        end
    end
    
    return Volume(bounds, faces)
end

function updatebounds!(box, face)
    xordering = findorder(face.vertices, 1)
    yordering = findorder(face.vertices, 2)
    zordering = face.heights

    box.minX = min(face.vertices[xordering[1]][1], box.minX)
    box.minY = min(face.vertices[yordering[1]][2], box.minY)
    box.minZ = min(face.vertices[zordering[1]][3], box.minZ)
    box.maxX = max(face.vertices[xordering[3]][1], box.maxX)
    box.maxY = max(face.vertices[yordering[3]][2], box.maxY)
    box.maxZ = max(face.vertices[zordering[3]][3], box.maxZ)
end

function getface(m::IOStream)
    #  facet normal -1 0 0
    #    outer loop
    #      vertex 0 0 10
    #      vertex 0 10 10
    #      vertex 0 0 0
    #    endloop
    #  endfacet
    vertices = Array[]
    normal = zeros(3)
    line = split(lowercase(readline(m)))
    if line[1] == "facet"
        normal = float64(line[3:5])
        readline(m) # Throw away outerloop
        for i = 1:3 # Get vertices
            line = split(lowercase(readline(m)))
            push!(vertices, float64(line[2:4]))
        end
        # Find Height ordering
        heights = findorder(vertices, 3)

        return Face(vertices, normal, heights)
    else
        return Nothing
    end
    
end

function findorder(vertices::Array, index)
    # findheights
    # Given an array of vectors, return an ordered list of their maximum values.
    heights = ones(3)
    for i = 1:3
        if vertices[i][index] < vertices[heights[1]][index] #min
            heights[1] = i
        elseif vertices[i][index] > vertices[heights[3]][index] #max
            heights[3] = i
        elseif vertices[i][index] == vertices[heights[1]][index] #same as min
            heights[2] = heights[1]
        elseif vertices[i][index] == vertices[heights[3]][index] #same as max
            heights[2] = heights[3]
        else
            heights[2] = i
        end
    end
    return heights
end

function getlinesegment(p0, p1, p2, z)
    seg_start = Float64[]
    seg_end = Float64[]
    seg_start[1] = p0[1] + (p1[1] - p0[1]) * (z - p0[3]) / (p1[3] - p0[3]);
    seg_start[2] = p0[2] + (p1[2] - p0[2]) * (z - p0[3]) / (p1[3] - p0[3]);
    seg_end[1] = p0[1] + (p2[1] - p0[1]) * (z - p0[3]) / (p2[3] - p0[3]);
    seg_end[2] = p0[2] + (p2[2] - p0[2]) * (z - p0[3]) / (p2[3] - p0[3]);
    return seg_start, seg_end;
end

end # module
