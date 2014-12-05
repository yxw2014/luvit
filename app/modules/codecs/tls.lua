--[[

Copyright 2014 The Luvit Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]

local Object = require('core').Object

local bit = require('bit')
local openssl = require('openssl')
local table = require('table')

local _root_ca = require('codecs/_root_ca')
local _common_tls = require('codecs/_common_tls')

local DEFAULT_CERT_STORE = nil

--[[
callbacks
   onsecureConnect -- When handshake completes successfully
]]--

return function (options)
  local ctx, bin, bout, ssl, outerWrite, outerRead, waiting, handshake, sslRead
  local tls = {}

  -- Both sides will call handshake as they are hooked up
  -- But the first to call handshake will simply wait
  -- And the second will perform the handshake and then
  -- resume the other.
  function handshake()
    if outerWrite and outerRead then
      while true do
        local hs = ssl:handshake()
        p(hs)
        if hs then
          tls.verify()
          break
        end
        outerWrite(bout:read())
        local data = outerRead()
        if data then bin:write(data) end
      end
      assert(coroutine.resume(waiting))
      waiting = nil
    else
      waiting = coroutine.running()
      coroutine.yield()
    end
  end

  function sslRead()
    return ssl:read()
  end

  function tls.verify()
    if ctx.rejectUnauthorized then
      p('verify_result')
      local peer = ssl:peer()
      local verify = false
      local err

      p('peer', peer)
      if peer then
        p(peer:subject())
        verify, err = ssl:getpeerverification()
        p('verify', verify)
      end
      p(type(verify))

      if verify and tls.onsecureConnect then return tls.onsecureConnect() end
      if tls.onerror then tls.onerror(err) end
    else
      if tls.onsecureConnect then tls.onsecureConnect() end
    end
  end

  function tls.createContext(options)
    options = options or {}

    ctx = _common_tls.createCredentials(options)

    -- CA
    if options.ca then
      for _, v in pairs(options.ca) do
        print(v)
      end
      ctx:addCACert(options.ca)
    end

    bin, bout = ctx:createBIO()
    ssl = ctx:createSSLContext(bin, bout, false)

    tls.ctx = ctx.context
    tls.ssl = ssl
  end

  function tls.decoder(read, write)
    outerRead = read
    handshake()
    for cipher in read do
      bin:write(cipher)
      for data in sslRead do
        write(data)
      end
    end
    write()
  end

  function tls.encoder(read, write)
    outerWrite = write
    handshake()
    for plain in read do
      ssl:write(plain)
      while bout:pending() > 0 do
        local data = bout:read()
        write(data)
      end
    end
    ssl:shutdown()
    write()
  end

  tls.createContext(options)

  return tls
end