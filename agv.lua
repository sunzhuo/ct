--- 创建一个新的AGV对象
---@param targetCY 目标堆场
---@param targetContainer 目标集装箱{bay, col, level}
function AGV()
    local agv = scene.addobj("/res/ct/agv.glb")
    agv.type = "agv" -- 记录对象类型
    agv.speed = 10 -- agv速度
    agv.roty = 0 -- 以y为轴的旋转弧度，默认方向为0
    agv.tasksequence = {} -- 初始化任务队列
    agv.tasks = {} -- 可用任务列表(数字索引为可用任务，字符索引为任务函数)
    agv.container = nil -- 初始化集装箱
    agv.height = 2.10 -- agv平台高度

    -- 新增（by road)
    -- agv.safetyDistance = 5 -- 安全距离
    agv.safetyDistance = 20 -- 安全距离
    agv.road = nil -- 相对应road:registerAgv中设置agv的road属性.
    agv.state = nil -- 正常状态
    agv.targetContainerPos = nil -- 目标集装箱位置{bay, col, level}

    -- 绑定起重机（RMG/RMGQC）
    function agv:bindCrane(targetCY, targetContainer)
        agv.datamodel = targetCY -- 目标堆场(数据模型)
        agv.operator = targetCY.operator -- 目标场桥(操作器)
        agv.targetContainerPos = targetContainer -- 目标集装箱{bay, col, level}
        agv.arrived = false -- 是否到达目标
    end

    function agv:move2(x, y, z) -- 直接移动到指定坐标
        agv:setpos(x, y, z)
        agv:setrot(0, agv.roty, 0)
        if agv.container ~= nil then
            agv.container:setpos(x, y + agv.height, z)
            agv.container:setrot(0, agv.roty, 0)
        end
    end

    function agv:attach()
        agv.container = agv.operator.stash
        agv.operator.stash = nil
    end

    function agv:detach()
        agv.operator.stash = agv.container
        agv.container = nil
    end

    -- 注册任务，添加到任务列表中（主要方便debug）
    function agv:registerTask(taskname)
        table.insert(agv.tasks, taskname)
    end

    function agv:executeTask(dt) -- 执行任务 task: {任务名称,{参数}}
        if agv.tasksequence[1] == nil or #agv.tasksequence == 0 then
            return
        end

        local task = agv.tasksequence[1]
        local taskname, params = task[1], task[2]

        -- -- debug
        -- if agv.lasttask ~= taskname then
        --     print('[agv', agv.id, '] executing', taskname)
        --     agv.lasttask = taskname
        -- end

        if agv.tasks[taskname] == nil then
            print('[rmg] 错误，没有找到任务', taskname)
        end

        -- 执行任务
        if agv.tasks[taskname].execute ~= nil then
            agv.tasks[taskname].execute(dt, params)
            -- print('[agv', agv.id, '] task executing: ', taskname, 'dt=', dt)
        end
    end

    -- 添加任务
    function agv:addtask(name, param)
        local task = {name, param}
        table.insert(agv.tasksequence, task)
    end

    -- 删除任务
    function agv:deltask()
        -- 判断是否具有子任务序列
        if agv.tasksequence[1].subtask ~= nil and #agv.tasksequence[1].subtask > 0 then -- 子任务序列不为空，删除子任务中的任务
            table.remove(agv.tasksequence[1].subtask, 1)
            return
        end

        table.remove(agv.tasksequence, 1)

        if (agv.tasksequence[1] ~= nil and agv.tasksequence[1][1] == "attach") then
            print("[agv", agv.roadAgvId or agv.id, "] task executing: ", agv.tasksequence[1][1])
        end
    end

    function agv:maxstep() -- 初始化和计算最大允许步进时间
        local dt = math.huge -- 初始化步进
        if agv.tasksequence[1] == nil then -- 对象无任务，直接返回最大值
            print('此处agv无任务，maxstep直接返回math.huge')
            return dt
        end

        local taskname = agv.tasksequence[1][1] -- 任务名称
        local params = agv.tasksequence[1][2] -- 任务参数

        -- -- debug
        -- if agv.lastmaxstep ~= taskname then
        --     agv.lastmaxstep = taskname
        --     print('[agv' .. agv.id .. '] maxstep', taskname)
        -- end

        -- 计算maxstep
        if agv.tasks[taskname] ~= nil and agv.tasks[taskname].maxstep ~= nil then
            dt = agv.tasks[taskname].maxstep(params)
        end

        return dt
    end

    -- {"move2",x,z} 移动到指定位置 {x,z, 向量距离*2(3,4), moved*2(5,6), 初始位置*2(7,8)},occupy:当前占用道路位置
    agv.tasks.move2 = {
        execute = function(dt, params)
            if params.speed == nil then
                agv:maxstep() -- 计算最大步进
            end

            local ds = {params.speed[1] * dt, params.speed[2] * dt} -- xz方向移动距离
            params.movedXZ[1], params.movedXZ[2] = params.movedXZ[1] + ds[1], params.movedXZ[2] + ds[2] -- xz方向已经移动的距离

            -- 判断是否到达
            for i = 1, 2 do
                if params.vectorDistanceXZ[i] ~= 0 and (params[i] - params.originXZ[i] - params.movedXZ[i]) *
                    params.vectorDistanceXZ[i] <= 0 then -- 如果分方向到达则视为到达
                    agv:move2(params[1], 0, params[2])
                    agv:deltask()
                    return
                end
            end

            -- 设置步进移动
            agv:move2(params.originXZ[1] + params.movedXZ[1], 0, params.originXZ[2] + params.movedXZ[2])
        end,
        maxstep = function(params)
            local dt = math.huge -- 初始化本任务最大步进

            -- 初始判断
            if params.vectorDistanceXZ == nil then -- 没有计算出向量距离，说明没有初始化
                local x, _, z = agv:getpos() -- 获取当前位置

                params.vectorDistanceXZ = {params[1] - x, params[2] - z} -- xz方向需要移动的距离
                if params.vectorDistanceXZ[1] == 0 and params.vectorDistanceXZ[2] == 0 then
                    print("Exception: agv不需要移动", " currentoccupy=", params.occupy)
                    agv:deltask()
                    -- return
                    return agv:maxstep() -- 重新计算
                end

                params.movedXZ = {0, 0} -- xz方向已经移动的距离
                params.originXZ = {x, z} -- xz方向初始位置

                local l = math.sqrt(params.vectorDistanceXZ[1] ^ 2 + params.vectorDistanceXZ[2] ^ 2)
                params.speed = {params.vectorDistanceXZ[1] / l * agv.speed, params.vectorDistanceXZ[2] / l * agv.speed} -- xz向量速度分量
            end

            for i = 1, 2 do
                if params.vectorDistanceXZ[i] ~= 0 then -- 只要分方向移动，就计算最大步进
                    dt = math.min(dt, math.abs((params[i] - params.originXZ[i] - params.movedXZ[i]) / params.speed[i]))
                end
            end
            return dt
        end
    }
    agv:registerTask("move2") -- 注册任务

    -- {"attach"}
    agv.tasks.attach = {
        execute = function(dt, params)
            -- -- debug
            -- if agv.operator.stash ~= nil then
            --     print("[agv", agv.roadAgvId or agv.id, "] agv.operator.stash.tag=",
            --         agv.operator.stash ~= nil and agv.operator.stash.tag ~= nil and agv.operator.stash.tag[1] ..
            --             agv.operator.stash.tag[2] .. agv.operator.stash.tag[3], " isSameContainerPos=", agv.operator
            --             .stash ~= nil and agv.isSameContainerPosition(agv.targetContainerPos, agv.operator.stash.tag)) -- debug
            -- end

            if agv.operator.currentAgv ~= nil and agv.operator.currentAgv ~= agv then
                -- print('[agv', agv.roadAgvId or agv.id, '] detected operator currentAgv is not self') -- debug
                return
            end

            if agv.operator.stash == nil then
                print('[agv', agv.roadAgvId or agv.id, '] detected operator stash is nil') -- debug
                return
            end

            -- if agv.operator.currentAgv == self then
            --     print('[agv', agv.roadAgvId or agv.id, '] detected operator currentAgv is self(agv', self.id, ')') -- debug
            -- end

            if agv.isSameContainerPosition(agv.targetContainerPos, agv.operator.stash.tag) then -- agv装货(判断交换区是否有集装箱&集装箱所有权)
                agv:attach()
                print("[agv", agv.roadAgvId or agv.id, "] attached container(", agv.container.tag[1],
                    agv.container.tag[2], agv.container.tag[3], ") at ", coroutine.qtime(), ', agv target=',
                    agv.targetContainerPos[1], agv.targetContainerPos[2], agv.targetContainerPos[3])
                agv.container.tag = nil -- 清除集装箱原有的tag信息
                agv:deltask()
            end
        end
        -- 无需maxstep
    }
    agv:registerTask("attach") -- 注册任务

    -- {"detach"}
    agv.tasks.detach = {
        execute = function(dt, params)
            -- agv的attach任务:(moveon -> (arrived) -> detach -> waitrmg)
            if agv.taskType == 'unload' then
                agv.arrived = true
            end

            if agv.operator.currentAgv ~= nil and agv.operator.currentAgv ~= agv then
                -- print('[agv', agv.roadAgvId or agv.id, '] detected operator currentAgv is not self, is agv',
                --     agv.operator.currentAgv.id) -- debug
                return
            end

            if agv.operator.stash ~= nil then
                print('[agv', agv.roadAgvId or agv.id, '] detected operator stash not nil') -- debug
                return
            end

            -- if agv.operator.currentAgv == self then
            --     print('[agv', agv.roadAgvId or agv.id, '] detected operator currentAgv is self(agv', self.id, ')') -- debug
            -- end

            -- print("[agv", agv.roadAgvId or agv.id, "] operator stash not nil") -- debug
            print("[agv", agv.roadAgvId or agv.id, "] detached container(",
                agv.targetContainerPos == nil and 'targetPos=nil' or agv.targetContainerPos[1] ..
                    agv.targetContainerPos[2] .. agv.targetContainerPos[3], ") at ", coroutine.qtime())
            agv:detach()
            agv:deltask()
        end
        -- 无需maxstep
    }
    agv:registerTask("detach") -- 注册任务

    -- {"waitoperator",'load'/'unload'} 等待机械响应（agv装/卸货）
    agv.tasks.waitoperator = {
        execute = function(dt, params)
            -- agv的attach任务:(moveon -> (arrived) -> waitrmg -> attach)
            if agv.taskType == 'load' then
                agv.arrived = true
            end

            if agv.operator.currentAgv ~= nil and agv.operator.currentAgv ~= agv then
                return -- 如果当前operator操作的对象不是本身，则不需要继续判断，直接返回
            end

            -- 检测rmg.stash是否为空，如果为空则等待；否则完成任务
            if params[1] == 'load' then -- attach
                -- agv装货
                if agv.operator.stash ~= nil then -- operator已经将货物放到stash中
                    agv:deltask()
                end
            elseif params[1] == 'unload' then -- detach
                -- agv卸货
                if agv.operator.stash == nil then -- operator已经将货物取走
                    agv:deltask()
                    return
                end
            end
        end
        -- 无需maxstep
    }
    agv:registerTask("waitoperator") -- 注册任务

    -- {"moveon",{road=,distance=,targetDistance=,stay=}} 沿着当前道路行驶。注意事项：param可能为nil
    agv.tasks.moveon = {
        execute = function(dt, params)
            -- 获取道路
            local road = agv.road
            local roadAgvItem = road.agvs[agv.roadAgvId - road.agvLeaveNum]

            -- 判断前方是否被堵塞
            local agvAhead = road:getAgvAhead(agv.roadAgvId)
            if agvAhead ~= nil then
                -- 不是最后一个agv
                -- local d = agvAhead.distance - roadAgvItem.distance
                -- print('agv' .. agv.id, '与前方agv距离为', d, 't0=', coroutine.qtime())
                -- if d <= agv.safetyDistance then -- 前方被堵塞
                --     agv.state = "wait" -- 设置agv状态为等待
                --     print('agv' .. agv.id, '状态设置为等待')
                --     return -- 直接返回
                -- end

                -- -- 前方没有被堵塞
                -- agv.state = nil -- 解除agv前方堵塞的wait占用状态
                if agv.state == "wait" then
                    -- print('agv' .. agv.id, '应用wait状态')
                    return
                end
            else
                -- 是最后一个agv
                if (params == nil or params.targetDistance == nil or params.targetDistance == road.length) and
                    road.toNode ~= nil and road.toNode.agv ~= nil and agv:InSafetyDistance(road.toNode.agv) then -- agv目标是道路尽头，且前方节点被堵塞
                    agv.state = "wait" -- 设置agv状态为等待
                    return -- 直接返回
                end
            end

            -- 判断是否到达目标

            -- -- debug
            -- if dt < 0.00000001 then
            --     print('[agv', agv.id, '] moveon road=', agv.road.id, ' ,+dt=', dt, ', distance=',
            --         roadAgvItem.distance + dt * agv.speed, '>=targetDistance=', roadAgvItem.targetDistance, '?',
            --         roadAgvItem.distance + dt * agv.speed >= roadAgvItem.targetDistance)
            -- end
            if roadAgvItem.distance + dt * agv.speed >= roadAgvItem.targetDistance then
                -- 到达目标
                road:setAgvDistance(roadAgvItem.targetDistance, agv.roadAgvId) -- 设置agv位置为终点位置

                -- 判断是否连接节点，节点是否可用
                -- 如果节点可用，则删除本任务，否则阻塞
                -- todo 是否需要判断节点是否可用？前面已经返回
                if road.toNode ~= nil then
                    -- print('[agv', agv.id, '] road.toNode==', road.toNode, '. road', road.id, '.toNode.occupied=',
                    --     road.toNode.occupied, '\t param.targetDist=', param.targetDistance, ' ,road.length=', road.length)
                    if road.toNode.occupied then
                        -- 节点被占用，本轮等待
                        agv.state = "wait" -- 设置agv状态为等待
                        -- print('agv', agv.id, '前方节点(', road.toNode.id, ')被堵塞，正在等待') -- debug
                        return
                    end

                    agv.state = nil -- 解除agv前方节点导致的占用状态
                    -- 节点没有被占用且agv到达了道路尽头，才能设置节点占用
                    if params.targetDistance == nil or road.targetDistance == road.length then
                        -- if road.targetDistance == road.length then
                        road.toNode.occupied = true -- 设置节点占用
                        road.toNode.agv = agv -- 设置节点agv信息
                    end
                end

                -- 结束任务
                agv.state = nil -- 设置agv状态为空(正常)
                road:removeAgv(agv.roadAgvId) -- 从道路中移除agv
                agv:deltask()
                return
            end

            -- 步进
            road:setAgvPos(dt, agv.roadAgvId)
        end,
        maxstep = function(params)
            local dt = math.huge -- 初始化本任务最大步进

            -- 未注册道路
            if agv.road == nil or agv.state == 'stay' then
                if params.road == nil then -- agv未注册道路且没有输入道路参数
                    print("Exception: agv未注册道路")
                    agv:deltask()
                    return agv:maxstep() -- 重新计算
                end

                -- 注册道路
                params.road:registerAgv(agv, {
                    -- 输入参数，并使用registerAgv的nil检测
                    distance = params.distance,
                    targetDistance = params.targetDistance,
                    stay = params.stay
                })
            end

            -- 判断agv状态
            -- if agv.state == "wait" or (agv.road.toNode ~= nil and agv.road.toNode.occupied) then -- agv状态为等待
            if agv.road.toNode ~= nil and agv.road.toNode.occupied then -- agv状态为等待
                return dt -- 不做计算
            end

            dt = agv.road:maxstep(agv.roadAgvId) -- 使用road中的方法计算最大步进
            return dt
        end
    }
    agv:registerTask("moveon") -- 注册任务

    -- {"onnode", node, fromRoad, toRoad} 输入通过节点到达的道路id
    agv.tasks.onnode = {
        execute = function(dt, params)
            -- 默认已经占用了节点

            local function tryExitNode()
                local x, y, z = table.unpack(params[3].originPt)
                local radian = math.atan(params[3].vecE[1], params[3].vecE[3]) - math.atan(0, 1)
                agv.roty = radian -- 设置agv旋转，下面的move2会一起设置
                agv:move2(x, y, z) -- 到达目标

                -- 判断出口是否占用，如果占用则在Node中等待，阻止其他agv进入Node
                if #params[3].agvs > 0 then -- 目标道路是否有agv
                    local roadAgvList = params[3].agvs
                    if agv:InSafetyDistance(roadAgvList[#roadAgvList].agv) then
                        agv.state = "wait" -- 设置agv状态为等待
                        return false -- 本轮等待
                    end
                end

                -- 满足退出条件，删除本任务
                agv.state = nil -- 设置agv状态为空(正常)
                params[1].occupied = false -- 解除节点占用
                params[1].agv = nil -- 清空节点agv信息
                agv:deltask() -- 删除任务
                return true -- 本轮任务完成
            end

            local fromRoad = params[2]
            local toRoad = params[3]

            -- -- 在本节点终止任务
            -- if toRoad == nil then
            --     agv:deltask()
            --     return
            -- end

            -- 判断与前面的agv是否保持安全距离(不需要判断toRoad因为maxstep已经判断过了)
            if #toRoad.agvs > 0 and agv:InSafetyDistance(toRoad.agvs[#toRoad.agvs].agv) then
                agv.state = "wait" -- 设置agv状态为等待
                return -- 本轮等待
            end
            agv.state = nil -- 设置agv状态为空(正常)

            -- 判断是转弯还是直行的情况
            if params.angularSpeed == nil then
                -- 直线
                -- 计算步进
                local ds = agv.speed * dt

                -- 判断是否到达目标
                if params.arrived or math.abs(ds + params.walked) >= params[1].radius * 2 then
                    params.arrived = true
                    if tryExitNode() then
                        -- 显示轨迹
                        scene.addobj('polyline', {
                            vertices = {fromRoad.destPt[1], fromRoad.destPt[2], fromRoad.destPt[3], toRoad.originPt[1],
                                        toRoad.originPt[2], toRoad.originPt[3]}
                        })
                    end
                    return
                end

                -- 设置步进
                params.walked = params.walked + ds
                local x, y, z = agv:getpos()
                agv:move2(x + ds * fromRoad.vecE[1], y + ds * fromRoad.vecE[2], z + ds * fromRoad.vecE[3]) -- 设置agv位置
            else
                -- 转弯
                -- 计算步进
                local dRadian = params.angularSpeed * dt * params.direction
                if not params.arrived then
                    params.walked = params.walked + dRadian
                end

                -- 判断是否到达目标
                -- print('dRadian=', dRadian, 'param.walked=', param.walked, 'param.deltaRadian=', param.deltaRadian,'dt=', dt) -- debug
                -- if (dRadian + param.walked) / param.deltaRadian >= 1 then
                if params.walked / params.deltaRadian >= 1 then
                    params.arrived = true
                    if tryExitNode() then
                        -- 显示轨迹
                        scene.addobj('polyline', {
                            vertices = params.trail
                        })
                    end
                    return
                end

                -- 计算步进
                local _, y, _ = agv:getpos()
                local x, z = params.radius * math.sin(params.walked + params.turnOriginRadian) + params.center[1],
                    params.radius * math.cos(params.walked + params.turnOriginRadian) + params.center[3]

                -- 记录轨迹
                table.insert(params.trail, x)
                table.insert(params.trail, y)
                table.insert(params.trail, z)

                -- agv.roty = agv.roty + dRadian*2 --为什么要*2 ???
                agv.roty = math.atan(params[2].vecE[1], params[2].vecE[3]) + params.walked - math.atan(0, 1)

                -- 应用计算结果
                agv:move2(x, y, z)
            end
        end,
        maxstep = function(params)
            local dt = math.huge -- 初始化本任务最大步进

            -- 默认已经占用了节点
            agv.road = nil -- 清空agv道路信息
            local node = params[1]
            -- 获取道路信息
            local fromRoad = params[2]
            local toRoad = params[3]

            -- 判断是否初始化
            if params.deltaRadian == nil then
                -- 判断是否在本节点终止
                if toRoad == nil then
                    -- 在本节点终止
                    node.occupied = false -- 解除节点占用
                    node.agv = nil -- 清空节点agv信息
                    agv:deltask()

                    return -1 -- 需要空转到execute删除任务，可能触发删除实体
                end

                -- 获取fromRoad的终点坐标。由于已知角度，toRoad的起点坐标就不需要了
                local fromRoadEndPoint = fromRoad.destPt -- {x,y,z}

                -- 到达节点（转弯）
                -- 计算需要旋转的弧度(两条道路向量之差的弧度，Road1->Road2)
                params.fromRadian = math.atan(fromRoad.vecE[1], fromRoad.vecE[3]) - math.atan(0, 1)
                params.toRadian = math.atan(toRoad.vecE[1], toRoad.vecE[3]) - math.atan(0, 1)
                params.deltaRadian = params.toRadian - params.fromRadian
                -- 模型假设弧度变化在-pi~pi之间，检测是否在这个区间内，如果不在需要修正
                if math.abs(params.deltaRadian) >= math.pi then
                    params.deltaRadian = params.deltaRadian * (1 - math.pi * 2 / math.abs(params.deltaRadian))
                end
                params.walked = 0 -- 已经旋转的弧度/已经通过的直线距离

                -- 判断是否需要转弯（可能存在直线通过的情况）
                if params.deltaRadian % math.pi ~= 0 then
                    params.radius = node.radius / math.tan(math.abs(params.deltaRadian) / 2) -- 转弯半径
                    -- debug
                    -- print('node radius:', node.radius, 'param deltaRadian:', param.deltaRadian)
                    -- print('radius:', param.radius)

                    -- 计算圆心
                    -- 判断左转/右转，左转deltaRadian > 0，右转deltaRadian < 0
                    params.direction = params.deltaRadian / math.abs(params.deltaRadian) -- 用于设置步进方向

                    -- 向左旋转90度坐标为(z,-x)，向右旋转90度坐标为(-z,x)
                    if params.deltaRadian > 0 then
                        -- 左转
                        -- 向左旋转90度vecE坐标变为(z,-x)
                        params.center = {fromRoadEndPoint[1] + params.radius * fromRoad.vecE[3], fromRoadEndPoint[2],
                                         fromRoadEndPoint[3] + params.radius * -fromRoad.vecE[1]}
                        params.turnOriginRadian = math.atan(-fromRoad.vecE[3], fromRoad.vecE[1]) -- 转弯圆的起始位置弧度(右转)
                    else
                        -- 右转
                        -- 向右旋转90度vecE坐标变为(-z,x)
                        params.center = {fromRoadEndPoint[1] + params.radius * -fromRoad.vecE[3], fromRoadEndPoint[2],
                                         fromRoadEndPoint[3] + params.radius * fromRoad.vecE[1]}
                        params.turnOriginRadian = math.atan(fromRoad.vecE[3], -fromRoad.vecE[1]) -- 转弯圆的起始位置弧度(左转)
                    end

                    -- debug
                    -- print('agv', agv.id, '在node', node.id, (param.deltaRadian > 0 and '左' or '右'),
                    --     '转 (deltaRadian=', param.deltaRadian, '):fromRadian', param.fromRadian, ', toRadian',
                    --     param.toRadian)

                    -- 显示转弯圆心
                    scene.addobj('points', {
                        vertices = params.center,
                        color = 'red',
                        size = 5
                    })
                    -- 显示半径连线
                    scene.addobj('polyline', {
                        vertices = {fromRoadEndPoint[1], fromRoadEndPoint[2], fromRoadEndPoint[3], params.center[1],
                                    params.center[2], params.center[3], toRoad.originPt[1], toRoad.originPt[2],
                                    toRoad.originPt[3]},
                        color = 'red'
                    })
                    -- 计算两段半径的长度
                    local l1 = math.sqrt((fromRoadEndPoint[1] - params.center[1]) ^ 2 +
                                             (fromRoadEndPoint[2] - params.center[2]) ^ 2 +
                                             (fromRoadEndPoint[3] - params.center[3]) ^ 2)
                    local l2 = math.sqrt((toRoad.originPt[1] - params.center[1]) ^ 2 +
                                             (toRoad.originPt[2] - params.center[2]) ^ 2 +
                                             (toRoad.originPt[3] - params.center[3]) ^ 2)
                    -- print('Rfrom:', l1, '\tRto:', l2) --debug
                    -- 初始化轨迹
                    params.trail = {fromRoadEndPoint[1], fromRoadEndPoint[2], fromRoadEndPoint[3]}

                    -- 计算角速度
                    params.angularSpeed = agv.speed / params.radius
                end
            end

            -- 计算最大步进
            local timeRemain
            if params.deltaRadian == 0 then
                -- 直线通过，不存在角速度
                local distanceRemain = node.radius * 2 - params.walked -- 计算剩余距离
                timeRemain = math.abs(distanceRemain / agv.speed)
            else
                -- 转弯，存在角速度
                local radianRemain = params.deltaRadian - params.walked -- 计算剩余弧度
                timeRemain = math.abs(radianRemain / params.angularSpeed)
            end

            dt = agv.state == nil and timeRemain or dt -- 计算最大步进，跳过agv等待状态的情况
            return dt
        end
    }
    agv:registerTask("onnode") -- 注册任务

    -- {"register", operator}
    -- todo 引发错误
    agv.tasks.register = {
        maxstep = function(params)
            if params == nil then
                print('[agv] register错误，没有operator参数')
                os.exit()
            end

            params:registerAgv(agv)

            agv:deltask() -- 删除任务
            return -1 -- maxstep触发重算
        end
    }
    agv:registerTask("register") -- 注册任务

    function agv:InSafetyDistance(targetAgv)
        local tx, ty, tz = targetAgv:getpos()
        local x, y, z = agv:getpos()
        local d = math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2)
        return d < agv.safetyDistance
    end

    function agv.isSameContainerPosition(pos1, pos2)
        if pos1 == nil or pos2 == nil then
            return false
        end
        return pos1[1] == pos2[1] and pos1[2] == pos2[2] and pos1[3] == pos2[3]
    end

    return agv
end
