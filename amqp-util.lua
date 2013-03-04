--
-- AMQP/RabbitMQ utilities and helper functions  for LuaJIT
-- Requires at least librrabbitmq.so.1.0
--
-- Copyright (c) 2013, Todd Coram. All rights reserved.
-- See LICENSE for details.
--

local ffi = require("ffi")

local A = require "amqp"
local M = { }

function M.connect_rabbit(opt)
   local opt = opt or {}
   local host = opt.host or "127.0.0.1"
   local port = opt.port or 5672
   local vhost = opt.vhost or "/"
   local user = opt.user or "guest"
   local password = opt.password or "guest"
   local channel = opt.channel or 1

   local conn=A.amqp_new_connection()
   local sockfd = M.die_on_error(A.amqp_open_socket(host,port),"Can't open socket.")

   A.amqp_set_sockfd(conn,sockfd)

   M.die_on_amqp_error(A.amqp_login(conn, vhost, 0, 131072, 0, 0, user, password),
		       "Can't login.")

   A.amqp_channel_open(conn,channel)
   M.die_on_amqp_error(A.amqp_get_rpc_reply(conn), "Can't open channel.")
   return conn
end

function M.disconnect_rabbit(conn,opt)
   local opt = opt or {}
   local channel = opt.channel or 1
   M.die_on_amqp_error(A.amqp_channel_close(conn,channel,A.AMQP_REPLY_SUCCESS),
		       "Closing channel.")
   M.die_on_amqp_error(A.amqp_connection_close(conn,A.AMQP_REPLY_SUCCESS),
		       "Closing connection.")
   M.die_on_error(A.amqp_destroy_connection(conn), 
		  "Ending Connection.")
end

function M.declare_exchange(conn,ename,etype,opt)
   local opt = opt or {}
   local channel = opt.channel or 1
   local passive = opt.passive or 0
   local durable = opt.durable or 0
   A.amqp_exchange_declare(conn, channel, 
			   A.amqp_cstring_bytes(ename), 
			   A.amqp_cstring_bytes(etype), 
			   passive, durable, A.amqp_empty_table)
   M.die_on_amqp_error(A.amqp_get_rpc_reply(conn), "Declaring exchange")
end

function M.declare_queue(conn,name,opt)
   local opt = opt or {}
   -- Can't handle autonamed queues (yet)
   --   local name = opt.name or ""
   local channel = opt.channel or 1
   local passive = opt.passive or 0
   local durable = opt.durable or 0
   local exclusive = opt.exclusive or 0
   local auto_delete = opt.autodelete or 0
   A.amqp_queue_declare(conn, channel, 
			A.amqp_cstring_bytes(name), passive, durable, exclusive,
			auto_delete, A.amqp_empty_table)
   M.die_on_amqp_error(A.amqp_get_rpc_reply(conn), "Declaring queue.")
end

function M.bind_queue(conn,name,exchange,opt)
   local opt = opt or {}
   local channel = opt.channel or 1
   local bindingkey = opt.bindingkey or ""
   A.amqp_queue_bind(conn, channel,
		     A.amqp_cstring_bytes(name),
		     A.amqp_cstring_bytes(exchange),
		     A.amqp_cstring_bytes(bindingkey),
		     A.amqp_empty_table)
   M.die_on_amqp_error(A.amqp_get_rpc_reply(conn), "Binding queue.")
end

function M.create_consumer(conn,queuename,cbfunc,opt)
   local opt = opt or {}
   local channel = opt.channel or 1
   local consumer_tag = opt.consumer_tag or queuename
   local no_local = opt.no_local or 0
   local no_ack = opt.no_ack or 0
   local exclusive = opt.exclusive or 0

   A.amqp_basic_consume(conn,channel,
			A.amqp_cstring_bytes(queuename),
			A.amqp_cstring_bytes(consumer_tag),
			no_local, no_ack, exclusive, A.amqp_empty_table)
   M.die_on_amqp_error(A.amqp_get_rpc_reply(conn), "Consuming.")
   f = function(delinfo,data)
      cbfunc(consumer_tag,data)
      if no_ack == 0 then 
	 A.amqp_basic_ack(conn,channel, delinfo.delivery_tag, 0) 
      end

   end
   return f
end


function M.wait_for_messages(conn,consumers)
   local result 
   local frame = ffi.new("amqp_frame_t",{})
   local body_target
   local body_received
   local consumer_tbl = {}

   for q,fo in pairs(consumers) do 
      f,opts = fo[1],fo[2]
      consumer_tbl[q] = M.create_consumer(conn,q,f,opts)
   end

   while true do
      local databuf = ""
      A.amqp_maybe_release_buffers(conn)
      result=A.amqp_simple_wait_frame(conn,frame)
      if result < 0 then break end
      if frame.frame_type == A.AMQP_FRAME_METHOD and 
	 frame.payload.method.id == A.AMQP_BASIC_DELIVER_METHOD then
	 local delinfo = ffi.cast("amqp_basic_deliver_t *", frame.payload.method.decoded)
	 result=tonumber(A.amqp_simple_wait_frame(conn,frame))
	 if result < 0 then break end
	 if frame.frame_type ~= A.AMQP_FRAME_HEADER then
	    error("Expected header!")
	 end
	 body_target = tonumber(frame.payload.properties.body_size)
	 body_received = 0
	 while body_received  < body_target do
	    result=tonumber(A.amqp_simple_wait_frame(conn,frame))
	    if result < 0 then break end
	    if frame.frame_type ~= A.AMQP_FRAME_BODY then
	       error("Expected header!")
	    end
	    body_received = body_received + tonumber(frame.payload.body_fragment.len)

	    databuf = databuf .. ffi.string(frame.payload.body_fragment.bytes,
					    tonumber(frame.payload.body_fragment.len))
	 end
	 tag=ffi.string(delinfo.consumer_tag.bytes,delinfo.consumer_tag.len)
	 consumer_tbl[tag](delinfo,databuf)
      end
   end
end

function M.publish(conn,exchange,msg,opt)
   local opt = opt or {}
   local channel = opt.channel or 1
   local mandatory = opt.mandatory or 0
   local immediate = opt.immediate or 0
   local bindingkey = opt.bindingkey or ""
   local routingkey = opt.routingkey or ""
   local properties = opt.properties or nil
   
   buf = A.amqp_bytes_malloc(#msg)
   ffi.copy(buf.bytes,msg,#msg)
   buf.len = #msg

   io.write(string.format("%d\n",tonumber(buf.len)))
   A.amqp_basic_publish(conn, channel, 
			A.amqp_cstring_bytes(exchange),  
			A.amqp_cstring_bytes(routingkey),
			mandatory, immediate, properties,
			buf)

   A.amqp_bytes_free(buf)

   M.die_on_amqp_error(A.amqp_get_rpc_reply(conn), "Publish.")
end


function M.die_on_error(t,msg)
   assert(t,msg)
   return t
end

function M.die_on_amqp_error(v,msg)
   rep=tonumber(v.reply_type)
   if rep < 2 then 
      return v
   elseif rep == 2 then
      error(msg .. ": AMQP_RESPONSE_LIBRARY_EXCEPTION")
   elseif rep == 3 then
      error(string.format(msg .. ": AMQP_RESPONSE_SERVER_EXCEPTION: %d", v.reply.id))
   else
      error(msg .. ": UNKNOWN AMQP EXCEPTION")
   end
end


setmetatable(M, { __index = A })
return M