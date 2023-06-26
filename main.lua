local Mod = RegisterMod("I.S.A.A.C", 1)
local game = Game()
local sfx = SFXManager()

--[[

	TODO:
		- Add Judas Birthright effect
		- Mouse support
		- Steamdeck

]]--

--[[

	Hey! Looking into my code to see how I do things? Don't!

	This isn't me being smug or asking you not to steal code,
	this file is just a huge mess and won't be of any help for looking into stuff.
	
	If you're looking through here to see how I do a thing, consider messaging me directly
	since I'll probably have a much better way to do half the things in this mod than how they're done here.
	
	- Barney

]]--

SoundEffect.SOUND_VATS_ENTER = Isaac.GetSoundIdByName("Vats Enter")
SoundEffect.SOUND_VATS_MOVE = Isaac.GetSoundIdByName("Vats Move")
SoundEffect.SOUND_VATS_READY = Isaac.GetSoundIdByName("Vats Ready")

Mod.COLLECTIBLE_VATS = Isaac.GetItemIdByName("I.S.A.A.C")

local shoot_time_offset = 20

-- Time freezing

local frozen_entities = {}
local freeze_time = 0
local shoot_time = 0

local frozen_entity_data = {}

-- Selection Logic

local primed_enemies = {}
local selected_enemy = 0

local primed_enemy_menu_data = {}
local isaac_menu_data = {}

local menu_cooldown_up = false
local menu_cooldown_down = false
local menu_cooldown_left = false
local menu_cooldown_right = false
local menu_cooldown_active = false

-- Keeping track of entities

local used_player = 0
local used_player_incubus = {}

function Mod:onGameStart()

	freeze_time = 0
	shoot_time = 0

end

Mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Mod.onGameStart)

function Mod:ActivateVATS(item, rng, player)

	if item ~= Mod.COLLECTIBLE_VATS then return end
	if shoot_time > game:GetFrameCount() then return {
		Discharge = false,
		Remove = false,
		ShowAnim = false
	} end
	
	menu_cooldown_up = true
	menu_cooldown_down = true
	menu_cooldown_left = true
	menu_cooldown_right = true
	menu_cooldown_active = true
	
	frozen_entities = {}
	frozen_entity_data = {}
	primed_enemies = {}
	primed_enemy_menu_data = {}
	selected_enemy = 0
	
	used_player_incubus = {}
	
	for i, entity in ipairs(Isaac.GetRoomEntities()) do
	
		local entity_data = {}
	
		-- Different freezing logic for different entity types
		-- For most entities we can rely on the FREEZE flag, but otherwise we have to hold them in place manually
	
		if entity.Type == EntityType.ENTITY_PROJECTILE then
			entity_data = {
			
				Velocity = entity.Velocity,
				FallingAccel = entity:ToProjectile().FallingAccel,
				FallingSpeed = entity:ToProjectile().FallingSpeed,
				HomingStrength = entity:ToProjectile().HomingStrength
			
			}
			entity.Velocity = entity_data.Velocity * 0
			entity:ToProjectile().FallingAccel = -0.1
			entity:ToProjectile().FallingSpeed = 0
			entity:ToProjectile().HomingStrength = 0
		elseif entity.Type == EntityType.ENTITY_TEAR then
			entity_data = {
			
				Velocity = entity.Velocity,
				FallingAcceleration = entity:ToTear().FallingAcceleration,
				FallingSpeed = entity:ToTear().FallingSpeed,
				HomingFriction = entity:ToTear().HomingFriction
			
			}
			entity.Velocity = entity_data.Velocity * 0
			entity:ToTear().FallingAcceleration = -0.1
			entity:ToTear().FallingSpeed = 0
			entity:ToTear().HomingFriction = 0
		elseif entity.Type == EntityType.ENTITY_FAMILIAR then
			entity_data = {
			
				Position = entity.Position,
				Velocity = entity.Velocity,
				FireCooldown = entity:ToFamiliar().FireCooldown
			
			}
			entity.Velocity = entity_data.Velocity * 0
			
			-- Special synergy privilage for Incubus
			-- Honestly this is just so Lilith doesn't look weird
			
			if entity.Variant == FamiliarVariant.INCUBUS and entity:ToFamiliar().Player.Index == player.Index then
				table.insert(used_player_incubus, entity)
			end
			
		elseif entity.Type == EntityType.ENTITY_PLAYER then
			entity_data = {
			
				Position = entity.Position,
				Velocity = entity.Velocity,
				FireDelay = entity:ToPlayer().FireDelay
			
			}
			entity.Velocity = entity_data.Velocity * 0
		elseif entity.Type == EntityType.ENTITY_EFFECT then
			entity_data = {
			
				Position = entity.Position,
				Velocity = entity.Velocity
			
			}
			entity.Velocity = entity_data.Velocity * 0
		else
			--entity:AddFreeze(EntityRef(player), 300)
			entity:AddEntityFlags(EntityFlag.FLAG_FREEZE)
			entity_data = {
			
				Position = entity.Position,
				Velocity = entity.Velocity
			
			}
			if entity:IsVulnerableEnemy() then
				table.insert(primed_enemies, entity)
			end
		end
		
		table.insert(frozen_entities, entity)
		table.insert(frozen_entity_data, entity_data)
		
	end
	
	-- This is all the logic that makes selecting an enemy intuitive
	-- Basically it just estimates where the cursor should go when you press certain buttons on certain enemies
	-- It's not perfect, but it's as close as I can get to making functional UX on the fly
	-- You have a huge window to select enemies, at least
	
	local default_enemy_directions = {
	
		up = 0,
		down = 0,
		left = 0,
		right = 0
	
	}
	
	for i = 1, #primed_enemies do
	
		local enemy = primed_enemies[i]
	
		if default_enemy_directions.up ~= 0 then
		
			if primed_enemies[default_enemy_directions.up].Position.Y < enemy.Position.Y then
			
				default_enemy_directions.up = i
			
			end
			if primed_enemies[default_enemy_directions.down].Position.Y > enemy.Position.Y then
			
				default_enemy_directions.down = i
			
			end
			if primed_enemies[default_enemy_directions.left].Position.X < enemy.Position.X then
			
				default_enemy_directions.left = i
			
			end
			if primed_enemies[default_enemy_directions.right].Position.X > enemy.Position.X then
			
				default_enemy_directions.right = i
			
			end
		
		else
		
			default_enemy_directions = {
			
				up = 1,
				down = 1,
				left = 1,
				right = 1
			
			}
		
		end
	
	end
	
	for i = 0, #primed_enemies do
	
		local enemy = primed_enemies[i]
	
		if i == 0 then
		
			enemy = player
		
		end
		
		local enemy_directions = {
	
			up = 0,
			down = 0,
			left = 0,
			right = 0
		
		}
		
		for o = 1, #primed_enemies do
		
			if o ~= i then
		
				local compare_enemy = primed_enemies[o]
				local compare_difference = compare_enemy.Position - enemy.Position
				
				local y_cone = (math.abs(compare_difference.Y) > math.abs(compare_difference.X))
				
				if y_cone then
					
					if compare_difference.Y < 0 then
						if enemy_directions.up == 0 then
							enemy_directions.up = o
						elseif primed_enemies[enemy_directions.up].Position.Y < compare_enemy.Position.Y then
							enemy_directions.up = o
						end
					end
					
					if compare_difference.Y > 0 then
						if enemy_directions.down == 0 then
							enemy_directions.down = o
						elseif primed_enemies[enemy_directions.down].Position.Y > compare_enemy.Position.Y then
							enemy_directions.down = o
						end
					end
					
				else
					
					if compare_difference.X < 0 then
						if enemy_directions.left == 0 then
							enemy_directions.left = o
						elseif primed_enemies[enemy_directions.left].Position.X < compare_enemy.Position.X then
							enemy_directions.left = o
						end
					end
					
					if compare_difference.X > 0 then
						if enemy_directions.right == 0 then
							enemy_directions.right = o
						elseif primed_enemies[enemy_directions.right].Position.X > compare_enemy.Position.X then
							enemy_directions.right = o
						end
					end
					
				end
				
			end
		
		end
		
		if enemy_directions.up == 0 then
			enemy_directions.up = default_enemy_directions.up
		end
		if enemy_directions.down == 0 then
			enemy_directions.down = default_enemy_directions.down
		end
		if enemy_directions.left == 0 then
			enemy_directions.left = default_enemy_directions.left
		end
		if enemy_directions.right == 0 then
			enemy_directions.right = default_enemy_directions.right
		end
		
		if i == 0 then
		
			isaac_menu_data = enemy_directions
			
		else
		
			table.insert(primed_enemy_menu_data, enemy_directions)
			
		end
	
	end
	
	freeze_time = game:GetFrameCount() + 300
	shoot_time = freeze_time + shoot_time_offset
	sfx:Play(SoundEffect.SOUND_VATS_ENTER, 2, 0, false, 1, 0)
	
	used_player = player
	
	return {
		Discharge = true,
		Remove = false,
		ShowAnim = true
	}

end

Mod:AddCallback(ModCallbacks.MC_USE_ITEM, Mod.ActivateVATS, Mod.COLLECTIBLE_VATS)

function Mod:onUpdate()
	
	if freeze_time > game:GetFrameCount() then
		
		if primed_enemies[selected_enemy] ~= nil then
			primed_enemies[selected_enemy]:SetColor(Color(0, 1, 0, 1, 0, 255, 0), 1, 1, false, false)
		end
		
		for i = 1, #frozen_entities do
		
			local entity = frozen_entities[i]
			local entity_data = frozen_entity_data[i]
			
			if entity.Type == EntityType.ENTITY_PROJECTILE then
			
				entity:ToProjectile().ChangeTimeout = entity:ToProjectile().ChangeTimeout + 1
			
			elseif entity.Type == EntityType.ENTITY_FAMILIAR then
			
				entity.Velocity = Vector(0, 0)
				entity.Position = entity_data.Position
				entity:ToFamiliar().FireCooldown = entity_data.FireCooldown + 2
			
			elseif entity.Type == EntityType.ENTITY_PLAYER then
			
				entity.Velocity = Vector(0, 0)
				entity.Position = entity_data.Position
				entity:ToPlayer().FireDelay = entity_data.FireDelay + 2
				
			elseif entity.Type == EntityType.ENTITY_EFFECT then
			
				entity.Velocity = Vector(0, 0)
				entity.Position = entity_data.Position
			
			else
			
				entity:AddEntityFlags(EntityFlag.FLAG_FREEZE)
			
			end
		
		end
		
	elseif freeze_time == game:GetFrameCount() then
		Mod:doVatsFire()
	end
	
	if shoot_time > game:GetFrameCount() and freeze_time <= game:GetFrameCount() then
		local time_passed = game:GetFrameCount() - freeze_time
	
		if primed_enemies[selected_enemy] == nil then return end
	
		local has_car_battery = used_player:HasCollectible(CollectibleType.COLLECTIBLE_CAR_BATTERY)
	
		if time_passed % 2 == 0 and time_passed <= (9 * (has_car_battery and 2 or 1)) then
		
			local enemy_position = primed_enemies[selected_enemy].Position
			
			local do_player_shoot = used_player:ToPlayer():CanShoot() and 0 or 1
			
			if used_player:ToPlayer():CanShoot() or #used_player_incubus > 0 then
			
				for i = do_player_shoot, math.max(#used_player_incubus, do_player_shoot) do
				
					local entity_position = used_player.Position + used_player:ToPlayer().TearsOffset
					
					if i > 0 then
						entity_position = used_player_incubus[i].Position
					end
					
					local calc_velocity = enemy_position - entity_position
					
					local tear_angle = math.deg(math.atan(calc_velocity.Y/calc_velocity.X)) + (calc_velocity.X < 0 and 180 or 0)
					local tear_velocity = Vector.FromAngle(tear_angle + (math.random() * 10 - 5)) * 12
					
					
					if used_player:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) then
					
						used_player:FireBomb(entity_position, tear_velocity, used_player)
					
					elseif used_player:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X) then
					
						used_player:FireTechXLaser(entity_position, tear_velocity, 50, used_player, 1.2)
					
					-- I cannot get the lasers to spawn from Incubus, for some reason. Sorry lilith.
					elseif used_player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) and i == 0 then
					
						used_player:FireBrimstone(tear_velocity, used_player, 1.2)
					
					elseif used_player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY) then
					
						used_player:FireTechLaser(entity_position, LaserOffset.LASER_TECH1_OFFSET, tear_velocity, false, false, used_player, 1.2)
					
					else
					
						used_player:FireTear(entity_position, tear_velocity, true, true, false, used_player, 1.2)
					
					end
				
				end
				
			end
			
		end
	elseif shoot_time == game:GetFrameCount() then
		for i = 1, #frozen_entities do
			local entity = frozen_entities[i]
			entity:ClearEntityFlags(EntityFlag.FLAG_SLOW)
		end
	end

end

Mod:AddCallback(ModCallbacks.MC_POST_UPDATE, Mod.onUpdate)

function Mod:onInput(entity, hook, action)

	if freeze_time < game:GetFrameCount() then return end
	if entity == nil then return end
	if hook == InputHook.GET_ACTION_VALUE then

		if action == ButtonAction.ACTION_LEFT then
		
			if Input.GetActionValue(action, entity:ToPlayer().ControllerIndex) > 0.1 then
			
				if menu_cooldown_left then return 0 end
				
				if #primed_enemies > 0 then
				
					if selected_enemy == 0 then
						selected_enemy = isaac_menu_data.left
					else
						selected_enemy = primed_enemy_menu_data[selected_enemy].left
					end
					
					Mod.doVatsSelect()
				end
				menu_cooldown_left = true
			else
				menu_cooldown_left = false
			end
			
			return 0
		elseif action == ButtonAction.ACTION_RIGHT then
		
			if Input.GetActionValue(action, entity:ToPlayer().ControllerIndex) > 0.1 then
			
				if menu_cooldown_right then return 0 end
				
				if #primed_enemies > 0 then
				
					if selected_enemy == 0 then
						selected_enemy = isaac_menu_data.right
					else
						selected_enemy = primed_enemy_menu_data[selected_enemy].right
					end
				
					Mod.doVatsSelect()
				end
				menu_cooldown_right = true
			else
				menu_cooldown_right = false
			end
			
			return 0
		elseif action == ButtonAction.ACTION_UP then
		
			if Input.GetActionValue(action, entity:ToPlayer().ControllerIndex) > 0.1 then
			
				if menu_cooldown_up then return 0 end
				
				if #primed_enemies > 0 then
				
					if selected_enemy == 0 then
						selected_enemy = isaac_menu_data.up
					else
						selected_enemy = primed_enemy_menu_data[selected_enemy].up
					end
				
					Mod.doVatsSelect()
				end
				menu_cooldown_up = true
			else
				menu_cooldown_up = false
			end
			
			return 0
		elseif action == ButtonAction.ACTION_DOWN then
		
			if Input.GetActionValue(action, entity:ToPlayer().ControllerIndex) > 0.1 then
			
				if menu_cooldown_down then return 0 end
				
				if #primed_enemies > 0 then
				
					if selected_enemy == 0 then
						selected_enemy = isaac_menu_data.down
					else
						selected_enemy = primed_enemy_menu_data[selected_enemy].down
					end
				
					Mod.doVatsSelect()
				end
				menu_cooldown_down = true
			else
				menu_cooldown_down = false
			end
			return 0
		end
	
	end
	if hook == InputHook.IS_ACTION_PRESSED then
		if action == ButtonAction.ACTION_SHOOTLEFT then
			return false
		elseif action == ButtonAction.ACTION_SHOOTRIGHT then
			return false
		elseif action == ButtonAction.ACTION_SHOOTUP then
			return false
		elseif action == ButtonAction.ACTION_SHOOTDOWN then
			return false
		elseif action == ButtonAction.ACTION_ITEM then
			if Input.IsActionPressed(action, entity:ToPlayer().ControllerIndex) then
			
				if menu_cooldown_active then return false end
			
				Mod.doVatsFire()
				menu_cooldown_active = true
			else
				menu_cooldown_active = false
			end
			return false
		end
	end

end

Mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, Mod.onInput)

-- Selection Logic

function Mod:doVatsSelect()
	
	sfx:Play(SoundEffect.SOUND_VATS_MOVE, 2, 0, false, 1, 0)

end

-- Shooting Logic

function Mod:doVatsFire()

	freeze_time = game:GetFrameCount()
	shoot_time = game:GetFrameCount() + shoot_time_offset
	
	for i = 1, #frozen_entities do
		local entity = frozen_entities[i]
		local entity_data = frozen_entity_data[i]
		
		if entity.Type == EntityType.ENTITY_PROJECTILE then
			entity.Velocity = entity_data.Velocity
			entity:ToProjectile().FallingAccel = entity_data.FallingAccel
			entity:ToProjectile().FallingSpeed = entity_data.FallingSpeed
			entity:ToProjectile().HomingStrength = entity_data.HomingStrength
		elseif entity.Type == EntityType.ENTITY_TEAR then
			entity.Velocity = entity_data.Velocity
			entity:ToTear().FallingAcceleration = entity_data.FallingAcceleration
			entity:ToTear().FallingSpeed = entity_data.FallingSpeed
			entity:ToTear().HomingFriction = entity_data.HomingFriction
		elseif entity.Type == EntityType.ENTITY_FAMILIAR then
			entity.Velocity = entity_data.Velocity
			entity:ToFamiliar().FireCooldown = entity_data.FireCooldown
		elseif entity.Type == EntityType.ENTITY_PLAYER or entity.Type == EntityType.ENTITY_EFFECT then
			entity.Velocity = entity_data.Velocity
		else
			entity:ClearEntityFlags(EntityFlag.FLAG_FREEZE)
			entity:AddEntityFlags(EntityFlag.FLAG_SLOW)
		end
	end

	sfx:Play(SoundEffect.SOUND_VATS_READY, 2, 0, false, 1, 0)

end

-- Shader

function Mod:GetShaderParams(shaderName)

    if shaderName == 'VATS' then
	
		local enable_shader = 0.0
		
		if freeze_time > game:GetFrameCount() then
			enable_shader = 1.0
		end
	
		local params = {
			Time = Isaac.GetFrameCount(),
			Enabled = enable_shader
		}
        return params
    end
	
end

Mod:AddCallback(ModCallbacks.MC_GET_SHADER_PARAMS, Mod.GetShaderParams)

-- EID Compat

if EID then
	EID:addCollectible(Mod.COLLECTIBLE_VATS, "Freezes all enemies on screen#Select 1 enemy to fire a volley of 5 tears at them", "I.S.A.A.C", "en_us")
end