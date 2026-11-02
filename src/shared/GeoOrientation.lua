local GeoOrientation = {}

GeoOrientation.NORTH = Vector3.new(0, 0, -1)
GeoOrientation.SOUTH = Vector3.new(0, 0, 1)
GeoOrientation.EAST = Vector3.new(1, 0, 0)
GeoOrientation.WEST = Vector3.new(-1, 0, 0)

GeoOrientation.NORTH_LABEL = "-Z"
GeoOrientation.SOUTH_LABEL = "+Z"
GeoOrientation.EAST_LABEL = "+X"
GeoOrientation.WEST_LABEL = "-X"

function GeoOrientation.headingDegrees(lookVector)
    local flat = Vector3.new(lookVector.X, 0, lookVector.Z)
    if flat.Magnitude < 0.001 then
        return 0
    end
    flat = flat.Unit

    local degrees = math.deg(math.atan2(flat.X, -flat.Z))
    if degrees < 0 then
        degrees += 360
    end
    return degrees
end

function GeoOrientation.headingName(degrees)
    local names = {"N","NE","E","SE","S","SW","W","NW"}
    return names[math.floor((degrees + 22.5) / 45) % 8 + 1]
end

return GeoOrientation
