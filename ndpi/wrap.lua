#! /usr/bin/env luajit
--
-- wrap.lua
-- Copyright (C) 2016-2017 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the Apache License 2.0.
--

local ndpi_c = require("ndpi.c")
local lib_version, lib = ndpi_c.version, ndpi_c.lib

local ffi = require("ffi")
local C = ffi.C

---------------------------------------------------------- Identifier ------

local id_struct_ptr_t = ffi.typeof("ndpi_id_t*")
local id_struct_size  = lib.ndpi_detection_get_sizeof_ndpi_id_struct()

local function id_new(ctype)
   local id = ffi.cast(id_struct_ptr_t, C.malloc(id_struct_size))
   ffi.fill(id, id_struct_size)
   return id
end

local id_type = ffi.metatype("ndpi_id_t", {
   __new = id_new;
   __gc  = C.free;
})

---------------------------------------------------------------- Flow ------

local flow_struct_ptr_t = ffi.typeof("ndpi_flow_t*")
local flow_struct_size  = lib.ndpi_detection_get_sizeof_ndpi_flow_struct()

local function flow_new(ctype)
   local flow = ffi.cast(flow_struct_ptr_t, C.malloc(flow_struct_size))
   ffi.fill(flow, flow_struct_size)
   return flow
end

local flow_type = ffi.metatype("ndpi_flow_t", {
   __new = flow_new;
   __gc  = lib.ndpi_free_flow;
})

---------------------------------------------------- Detection Module ------

local detection_module_free, detection_module_new
local detection_module = {
   load_protocols_file = function (self, path)
      if lib.ndpi_load_protocols_file(self, path) ~= 0 then
         error("Unable to open file '" .. path .. "'")
      end
      return self  -- Allow chaining calls
   end;

   set_protocol_bitmask = function (self, bitmask)
      lib.ndpi_set_protocol_detection_bitmask2(self, bitmask)
      return self  -- Allow chaining calls
   end;

   process_packet = function (...)
      local proto = lib.ndpi_detection_process_packet(...)
      return proto.master_protocol, proto.protocol
   end;

   guess_undetected_protocol = function (...)
      local proto = lib.ndpi_guess_undetected_protocol(...)
      return proto.master_protocol, proto.protocol
   end;

   get_protocol_id = function (...)
      local ret = lib.ndpi_get_protocol_id(...)
      return (ret == -1) and nil or ret
   end;

   get_protocol_breed_name = lib.ndpi_get_proto_breed_name;
   get_protocol_breed = lib.ndpi_get_proto_breed;
   dump_protocols = lib.ndpi_dump_protocols;
}

if lib_version.major == 1 and lib_version.minor == 7 then
   detection_module_free = function (dm)
      lib.ndpi_exit_detection_module(ffi.gc(dm, nil), C.free)
   end

   detection_module_new = function (ctype, ticks_per_second)
      return lib.ndpi_init_detection_module(ticks_per_second, C.malloc, C.free, nil)
   end

   detection_module.find_port_based_protocol = function (...)
      local proto = lib.ndpi_find_port_based_protocol(...)
      return proto.master_protocol, proto.protocol
   end
else
   detection_module_free = lib.ndpi_exit_detection_module

   -- XXX: No ticks_per_second parameter here in newer versions.
   if lib_version.major >= 3 then
      -- TODO: Provide a way to specify the ndpi_init_prefs parameter.
      -- TODO: Split up the call to ndpi_finalize_initalization().
      detection_module_new = function (ctype, ticks_per_second)
         local dm = lib.ndpi_init_detection_module(0)
         lib.ndpi_finalize_initalization(dm)
         return dm
      end
   else
      detection_module_new = function (ctype, ticks_per_second)
         return lib.ndpi_init_detection_module()
      end
   end

   -- In nDPI 1.8 the second parameter (uint8_t proto) has been dropped.
   detection_module.find_port_based_protocol = function (dm, dummy, ...)
      local proto = lib.ndpi_find_port_based_protocol(dm, ...)
      return proto.master_protocol, proto.protocol
   end
end

if lib_version.major > 2 then
   detection_module.extra_dissection_possible = lib.ndpi_extra_dissection_possible
else
   -- nDPI 3.0 added ndpi_extra_dissection_possible(), which needs to be
   -- called to determine whether protocol specific fields are not yet
   -- dissected, in which case more data needs to be provided. In <3.0 all
   -- the fields are always provided at once when a match is reported.
   detection_module.extra_dissection_possible = function (dm, dummy)
      return false
   end
end

local detection_module_type = ffi.metatype("ndpi_detection_module_t", {
   __index = detection_module;
   __new   = detection_module_new;
   __gc    = detection_module_free;
})

------------------------------------------------------------- Exports ------

return {
   lib_version      = lib_version;
   id               = id_type;
   flow             = flow_type;
   detection_module = detection_module_type;
   protocol_bitmask = require("ndpi.protocol_bitmask").bitmask;
   protocol         = require("ndpi.protocol_ids_" .. lib_version.major .. "_" .. lib_version.minor);
}
