--[[
    Socket数据包数据类型
]]
local PACKET_DATA_TYPE = {}

PACKET_DATA_TYPE.UBYTE    = "ubyte"
PACKET_DATA_TYPE.BYTE     = "byte"
PACKET_DATA_TYPE.SHORT     = "short"
PACKET_DATA_TYPE.USHORT = "ushort"
PACKET_DATA_TYPE.INT     = "int"
PACKET_DATA_TYPE.UINT     = "uint"
PACKET_DATA_TYPE.LONG     = "long"
PACKET_DATA_TYPE.ULONG     = "ulong"
PACKET_DATA_TYPE.INT64     = "ulong"
PACKET_DATA_TYPE.STRING = "string"

PACKET_DATA_TYPE.ARRAY    = "array"

return PACKET_DATA_TYPE