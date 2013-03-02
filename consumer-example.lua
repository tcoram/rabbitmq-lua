rb=require "amqp-util"

conn = rb.connect_rabbit{host="localhost"}
rb.declare_exchange(conn, "LuaExchange", "fanout")
rb.bind_queue(conn, "LuaQueue","LuaExchange")
rb.consume(conn,"LuaQueue",print)
rb.disconnect_rabbit(conn)
