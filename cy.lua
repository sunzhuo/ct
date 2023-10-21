function CY(p1, p2, level)
    local cy = {
        clength = 6.06,
        cwidth = 2.44,
        cheight = 2.42,
        cspan = 0.6,
        containerPositions = {}, -- 堆场各集装箱位置坐标列表(bay,row,level)
        containers = {}, -- 集装箱对象(相对坐标)
        parkingSpaces = {}, -- 停车位对象(相对坐标)
        origin = {(p1[1] + p2[1]) / 2, 0, (p1[2] + p2[2]) / 2}, -- 参照点
        anchorPoint = {p1[1], 0, p1[2]}, -- 锚点
        queuelen = 16, -- 服务队列长度（额外）
        summon = {}, -- 车生成点
        exit = {}, -- 车出口
        agvspan = 2, -- agv间距
        containerUrls = {'/res/ct/container.glb', '/res/ct/container_brown.glb', '/res/ct/container_blue.glb',
                         '/res/ct/container_yellow.glb'},
        rotdeg = 0, -- 旋转角度
        bindingRoad = nil -- 绑定的道路
    }

    local pdx = (p2[1] - p1[1]) / math.abs(p1[1] - p2[1]) -- x方向向量
    local pdy = (p2[2] - p1[2]) / math.abs(p1[2] - p2[2]) -- y方向向量

    -- 计算属性
    cy.dir = {pdx, pdy} -- 方向
    cy.width, cy.length = math.abs(p1[1] - p2[1]), math.abs(p1[2] - p2[2])
    cy.row = math.floor((cy.width + cy.cspan) / (cy.cwidth + cy.cspan)) -- 行数
    cy.col = math.floor((cy.length + cy.cspan) / (cy.clength + cy.cspan)) -- 列数
    cy.marginx = (cy.width + cy.cspan - (cy.cwidth + cy.cspan) * cy.row) / 2 -- 横向外边距
    cy.rotradian = cy.rotdeg * math.pi / 180 -- 旋转弧度

    -- 集装箱层数
    cy.levels = {} -- 层数y坐标集合
    cy.level = level
    for i = 1, level + 2 do
        cy.levels[i] = cy.cheight * (i - 1)
    end

    for i = 1, cy.col do
        cy.containerPositions[i] = {} -- 初始化
        cy.containers[i] = {}
        for j = 1, cy.row do
            cy.containerPositions[i][j] = {}
            cy.containers[i][j] = {}
            for k = 1, cy.level do
                cy.containerPositions[i][j][k] = {p1[1] + pdx *
                    (cy.marginx + (j - 1) * (cy.cwidth + cy.cspan) + cy.cwidth / 2), cy.origin[2] + cy.levels[k],
                                                  p1[2] + pdy * ((i - 1) * (cy.clength + cy.cspan) + cy.clength / 2)}
                local url = cy.containerUrls[math.random(1, #cy.containerUrls)] -- 随机选择集装箱颜色
                cy.containers[i][j][k] = scene.addobj(url) -- 添加集装箱
                cy.containers[i][j][k]:setpos(cy.containerPositions[i][j][k][1], cy.containerPositions[i][j][k][2],
                    cy.containerPositions[i][j][k][3])
            end
        end
    end

    -- 旧版初始化队列(old)
    -- 新版初始化队列将bay投影到道路上，然后在道路上生成停车位。parkingSpacess记录道路上的相对信息。
    function cy:initqueue(iox) -- 初始化队列(cy.parkingSpaces) iox出入位置x相对坐标
        -- 停车队列(iox)
        cy.parkingSpaces = {} -- 属性：occupied:停车位占用情况，pos:停车位坐标，bay:对应堆场bay位

        -- 停车位
        for i = 1, cy.row do
            cy.parkingSpaces[i] = {} -- 初始化
            cy.parkingSpaces[i].occupied = 0 -- 0:空闲，1:临时占用，2:作业占用
            cy.parkingSpaces[i].pos = {cy.origin[1] + iox, 0,
                                       cy.origin[3] + cy.containerPositions[cy.row - i + 1][1][1][3]} -- x,y,z
            cy.parkingSpaces[i].bay = cy.row - i + 1
        end

        local lastbaypos = cy.parkingSpaces[1].pos -- 记录最后一个添加的位置

        -- 队列停车位
        for i = 1, cy.queuelen do
            local pos = {lastbaypos[1], 0, lastbaypos[3] - i * (cy.clength + cy.cspan)}
            table.insert(cy.parkingSpaces, 1, {
                occupied = 0,
                pos = pos
            }) -- 无对应bay
        end

        cy.summon = {cy.parkingSpaces[1].pos[1], 0, cy.parkingSpaces[1].pos[3]}
        cy.exit = {cy.parkingSpaces[1].pos[1], 0, cy.parkingSpaces[#cy.parkingSpaces].pos[3] + 20} -- 设置离开位置
    end

    -- 新版初始化队列
    function cy:bindRoad(road)
        -- 遍历bay坐标，进行投影
        local bayPos = {} -- bay的第一行坐标{x,z}
        for i = 1, cy.col do
            bayPos[i] = {cy.containerPositions[i][cy.row][1][1], cy.containerPositions[i][cy.row][1][3]}
        end

        -- 投影
        cy.parkingSpaces = {}
        for i = 1, #bayPos do
            cy.parkingSpaces[i] = {}
            cy.parkingSpaces[i].relativeDist = road:getVectorRelativeDist(bayPos[i][1], bayPos[i][2],
                math.cos(cy.rotradian - math.pi / 2), math.sin(cy.rotradian - math.pi / 2) * -1)
            -- print('cy debug: parking space', i, ' relative distance = ', cy.parkingSpaces[i].relativeDist)
        end

        -- 生成停车位并计算iox
        for k, v in ipairs(cy.parkingSpaces) do
            local x, y, z = road:getRelativePosition(v.relativeDist)

            -- 计算iox
            cy.parkingSpaces[k].iox = -1*math.sqrt((x - bayPos[k][1]) ^ 2 + (z - bayPos[k][2]) ^ 2)
            -- print('cy debug: parking space', k, ' iox = ', cy.parkingSpaces[k].iox)
        end

        cy.bindingRoad = road
    end

    --- 显示绑定道路对应的停车位点（debug用）
    function cy:showBindingPoint()
        -- 显示cy.parkingSpaces的位置
        for k, v in ipairs(cy.parkingSpaces) do
            local x, y, z = cy.bindingRoad:getRelativePosition(v.relativeDist)

            -- 显示位置
            scene.addobj('points', {
                vertices = {x, y, z},
                color = 'red',
                size = 5
            })
            local pointLabel = scene.addobj('label', {
                text = 'no.' .. k
            })
            pointLabel:setpos(x, y, z)

            -- print('cy debug: parking space', k, ' iox = ', cy.parkingSpaces[k].iox)
        end
    end

    return cy
end
