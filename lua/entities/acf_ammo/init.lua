
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

function ENT:Initialize()
    
    self.SpecialHealth      = true  --If true needs a special ACF_Activate function
    self.SpecialDamage      = true  --If true needs a special ACF_OnDamage function

    self.IsExplosive        = true
    self.Exploding          = false
    self.Damaged            = false

    self.CanUpdate          = true
    self.Load               = false
    self.EmptyMass          = 1
    self.AmmoMassMax        = 0
    self.NextMassUpdate     = 0

    self.Ammo               = 0
    self.IsTwoPiece         = false

    self.NextLegalCheck     = ACF.CurTime + math.random(ACF.Legal.Min, ACF.Legal.Max) -- give any spawning issues time to iron themselves out
    self.Legal              = true
    self.LegalIssues        = ""

    self.Active             = false
    self.Master             = {}
    self.Sequence           = 0
        
    self.Interval           = 1         -- Think Interval when its not damaged
    self.ExplosionInterval  = 0.01      -- Base Think Interval when its damaged and its about to explode

    self.Capacity           = 1         
    self.AmmoMassMax        = 1
    self.Caliber            = 1
    self.RoFMul             = 1
    self.LastMass           = 1

    self.Inputs             = Wire_CreateInputs( self, { "Active" } ) --, "Fuse Length"
    self.Outputs            = Wire_CreateOutputs( self, { "Munitions" } )

    ACF.AmmoCrates          = ACF.AmmoCrates or {}

end

function ENT:ACF_Activate( Recalc )

    local EmptyMass = math.max(self.EmptyMass, self:GetPhysicsObject():GetMass() - self.AmmoMassMax)

    self.ACF = self.ACF or {} 
    
    local PhysObj = self:GetPhysicsObject()

    if not self.ACF.Area then
        self.ACF.Area = PhysObj:GetSurfaceArea() * 6.45
    end

    if not self.ACF.Volume then
        self.ACF.Volume = PhysObj:GetVolume() * 16.38
    end
    
    local Armour    = EmptyMass*1000 / self.ACF.Area / 0.78 --So we get the equivalent thickness of that prop in mm if all it's weight was a steel plate
    local Health    = self.ACF.Volume/ACF.Threshold                         --Setting the threshold of the prop Area gone 
    local Percent   = 1 
    
    if Recalc and self.ACF.Health and self.ACF.MaxHealth then
        Percent = self.ACF.Health/self.ACF.MaxHealth
    end
    
    self.ACF.Health     = Health * Percent
    self.ACF.MaxHealth  = Health
    self.ACF.Armour     = Armour * (0.5 + Percent/2)
    self.ACF.MaxArmour  = Armour
    self.ACF.Type       = nil
    self.ACF.Mass       = self.Mass
    self.ACF.Density    = (self:GetPhysicsObject():GetMass()*1000) / self.ACF.Volume
    self.ACF.Type       = "Prop"

    self.ACF.Material     = not isstring(self.ACF.Material) and ACE.BackCompMat[self.ACF.Material] or self.ACF.Material or "RHA"

    --Forces an update of mass
    self.LastMass = 1 
    self:UpdateMass()

end

do

    local HEATtbl = {
        HEAT    = true,
        THEAT   = true,
        HEATFS  = true,
        THEATFS = true
    }

    local HEtbl = {
        HE      = true,
        HESH    = true,
        HEFS    = true
    }

    function ENT:ACF_OnDamage( Entity, Energy, FrArea, Angle, Inflictor, Bone, Type )   --This function needs to return HitRes

        local Mul       = (( HEATtbl[Type] and ACF.HEATMulAmmo ) or 1) --Heat penetrators deal bonus damage to ammo
        local HitRes    = ACF_PropDamage( Entity, Energy, FrArea * Mul, Angle, Inflictor ) --Calling the standard damage prop function
        
        if self.Exploding or not self.IsExplosive then return HitRes end
        
        if HitRes.Kill then

            if hook.Run("ACF_AmmoExplode", self, self.BulletData ) == false then return HitRes end

            self.Exploding = true

            if Inflictor and IsValid(Inflictor) and Inflictor:IsPlayer() then
                self.Inflictor = Inflictor
            end

            if self.Ammo > 1 and not (self.BulletData.Type == "Refill") then
                ACF_ScaledExplosion( self )
            else
                self:Remove()
            end
        end
        
        -- cookoff chance calculation
        if self.Damaged then return HitRes end

        if table.IsEmpty( self.BulletData or {} ) then  
            self:Remove()   
        else

            local Ratio     = ( HitRes.Damage/self.BulletData.RoundVolume )^0.2
            local CMul      = 1  --30% Chance to detonate, 5% chance to cookoff                                     
            local DetRand   = 0 

            --Heat penetrators deal bonus damage to ammo, 90% chance to detonate, 15% chance to cookoff
            if HEATtbl[Type] then 
                CMul = 6
            elseif HEtbl[Type] then
                CMul = 10    
            end 

            if self.BulletData.Type == "Refill" then
                DetRand = 0.75
            else
                DetRand = math.Rand(0,1) * CMul
            end
        
            --Cook Off
            if DetRand >= 0.95 then 

                self.Inflictor  = Inflictor
                self.Damaged    = ACF.CurTime + (5 - Ratio*3)

            --Boom
            elseif DetRand >= 0.7 then  

                self.Inflictor  = Inflictor
                self.Damaged    = 1 --Instant explosion guarenteed     

            end
    
        end

        return HitRes --This function needs to return HitRes
    end

end

function MakeACF_Ammo(Owner, Pos, Angle, Id, Data1, Data2, Data3, Data4, Data5, Data6, Data7, Data8, Data9, Data10, Data11, Data12, Data13, Data14, Data15)

    if not Owner:CheckLimit("_acf_ammo") then return false end
    
    local Ammo = ents.Create("acf_ammo")
    if not Ammo:IsValid() then return false end

    Ammo:SetAngles(Angle)
    Ammo:SetPos(Pos)
    Ammo:Spawn()
    Ammo:SetPlayer(Owner)
    Ammo.Owner = Owner
    
    Ammo.Model = ACF.Weapons.Ammo[Id].model 
    Ammo:SetModel( Ammo.Model ) 
    
    Ammo:PhysicsInit( SOLID_VPHYSICS )          
    Ammo:SetMoveType( MOVETYPE_VPHYSICS )       
    Ammo:SetSolid( SOLID_VPHYSICS )

    Ammo.Id = Id
    Ammo:CreateAmmo(Id, Data1, Data2, Data3, Data4, Data5, Data6, Data7, Data8, Data9, Data10, Data11, Data12, Data13, Data14, Data15)

    Ammo.Ammo       = Ammo.Capacity
    Ammo.EmptyMass  = ACF.Weapons.Ammo[Ammo.Id].weight or 1

    Ammo.AmmoMass   = Ammo.EmptyMass + Ammo.AmmoMassMax

    Ammo.LastMass   = 1
    Ammo:UpdateMass()

    Owner:AddCount( "_acf_ammo", Ammo )
    Owner:AddCleanup( "acfmenu", Ammo )
    
    table.insert(ACF.AmmoCrates, Ammo)
    
    return Ammo
end

list.Set( "ACFCvars", "acf_ammo", {"id", "data1", "data2", "data3", "data4", "data5", "data6", "data7", "data8", "data9", "data10", "data11", "data12", "data13", "data14", "data15"} )
duplicator.RegisterEntityClass("acf_ammo", MakeACF_Ammo, "Pos", "Angle", "Id", "RoundId", "RoundType", "RoundPropellant", "RoundProjectile", "RoundData5", "RoundData6", "RoundData7", "RoundData8", "RoundData9", "RoundData10" , "RoundData11", "RoundData12", "RoundData13", "RoundData14", "RoundData15" )


function ENT:Update( ArgsTable )
    
    -- That table is the player data, as sorted in the ACFCvars above, with player who shot, 
    -- and pos and angle of the tool trace inserted at the start

    local msg = "Ammo crate updated successfully!"
    
    if (CPPI and not self:CPPICanTool(ArgsTable[1])) or (not CPPI and ArgsTable[1] ~= self.Owner) then -- Argtable[1] is the player that shot the tool
        return false, "You don't own that ammo crate!"
    end
    
    if ArgsTable[6] == "Refill" then -- Argtable[6] is the round type. If it's refill it shouldn't be loaded into guns, so we refuse to change to it
        return false, "Refill ammo type is only avaliable for new crates!"
    end
    
    if ArgsTable[5] ~= self.RoundId then -- Argtable[5] is the weapon ID the new ammo loads into
        for Key, Gun in pairs( self.Master ) do
            if IsValid( Gun ) then
                Gun:Unlink( self )
            end
        end
        msg = "New ammo type loaded, crate unlinked."
    else -- ammotype wasn't changed, but let's check if new roundtype is blacklisted
        local Blacklist = ACF.AmmoBlacklist[ ArgsTable[6] ] or {}
        
        for Key, Gun in pairs( self.Master ) do
            if IsValid( Gun ) and table.HasValue( Blacklist, Gun.Class ) then
                Gun:Unlink( self )
                msg = "New round type cannot be used with linked gun, crate unlinked."
            end
        end
    end
    
    local AmmoPercent = self.Ammo/math.max(self.Capacity,1)
    
    self:CreateAmmo(ArgsTable[4], ArgsTable[5], ArgsTable[6], ArgsTable[7], ArgsTable[8], ArgsTable[9], ArgsTable[10], ArgsTable[11], ArgsTable[12], ArgsTable[13], ArgsTable[14], ArgsTable[15], ArgsTable[16], ArgsTable[17], ArgsTable[18], ArgsTable[19])   

    self.Ammo = math.floor(self.Capacity*AmmoPercent)
    
    self.LastMass = 1 -- force update of mass
    self:UpdateMass()
    
    return true, msg
    
end

function ENT:UpdateOverlayText()
    
    local roundType = self.RoundType
    
    if table.IsEmpty( self.BulletData or {} ) then  return end

    local text = ""

    if self.BulletData.Type == "Refill" then

        text = " - "..roundType.." - "

        if self.SupplyingTo and not table.IsEmpty(self.SupplyingTo) then
            text = text.."\nSupplying "..#self.SupplyingTo.." Ammo Crates"
        end

    else
        if self.BulletData.Tracer and self.BulletData.Tracer > 0 then 
            roundType = roundType .. "-T"
        end
    
        text = roundType .. " - " .. self.Ammo .. " / " .. self.Capacity

        local RoundData = ACF.RoundTypes[ self.RoundType ]
    
        if RoundData and RoundData.cratetxt then
            text = text .. "\n" .. RoundData.cratetxt( self.BulletData, self )
        end

        if self.IsTwoPiece then
            text = text .. "\nUses 2 piece ammo\n30% reload penalty"
        end
    end

    if not self.Legal then
        text = text .. "\n\nNot legal, disabled for " .. math.ceil(self.NextLegalCheck - ACF.CurTime) .. "s\nIssues: " .. self.LegalIssues
    end

    self:SetOverlayText( text )
    
end

do

    --List of ids which no longer stay on ACE. Useful to replace them with the closest counterparts
    local BackComp = {
        ["20mmHRAC"]        = "20mmRAC",
        ["30mmHRAC"]        = "30mmRAC",
        ["105mmSB"]         = "100mmSBC",
        ["120mmSB"]         = "120mmSBC",
        ["140mmSB"]         = "140mmSBC",
        ["170mmSB"]         = "170mmSBC",
        ["70mmFFARDAGR"]    = "70mmFFAR",
        ["9M113 ASM"]       = "9M133 ASM",
        ["9M311"]           = "9M311 SAM",
        ["SIMBAD-RC SAM"]   = "Mistral SAM"
    }

    --List of munitions no longer stay on ACE
    local AmmoComp = {
        ["APDSS"]          = "APDS",
        ["APFSDSS"]        = "APFSDS"  
    }

    function ENT:CreateAmmo(Id, Data1, Data2, Data3, Data4, Data5, Data6, Data7, Data8, Data9, Data10 , Data11 , Data12 , Data13 , Data14 , Data15)

        --Replaces id if its old
        self.RoundId = BackComp[Data1] or Data1 or "100mmC"

        local GunData = ACF.Weapons.Guns[self.RoundId]
        if not GunData then  
            self.RoundId = "100mmC"
            GunData = ACF.Weapons.Guns[self.RoundId]
        end

        --Data 1 to 4 are should always be Round ID, Round Type, Propellant lenght, Projectile lenght

        self.RoundType          = AmmoComp[ Data2 ] or ( ACE_CheckRound( Data2 ) and Data2 ) or "AP"   -- Type of round, IE AP, HE, HEAT ...
        self.RoundPropellant    = Data3                     or 0      -- Lenght of propellant
        self.RoundProjectile    = Data4                     or 0      -- Lenght of the projectile
        self.RoundData5         = Data5                     or 0
        self.RoundData6         = Data6                     or 0
        self.RoundData7         = Data7                     or 0
        self.RoundData8         = Data8                     or 0
        self.RoundData9         = Data9                     or 0
        self.RoundData10        = Data10                    or 0
        self.RoundData11        = Data11                    or 0   
        self.RoundData12        = Data12                    or 0   
        self.RoundData13        = Data13                    or 0   
        self.RoundData14        = Data14                    or 0   
        self.RoundData15        = Data15                    or 0
    
    
        local PlayerData = {}   --what a mess
        PlayerData.Id           = self.RoundId 
        PlayerData.Type         = self.RoundType 
        PlayerData.PropLength   = self.RoundPropellant 
        PlayerData.ProjLength   = self.RoundProjectile 
        PlayerData.Data5        = self.RoundData5 
        PlayerData.Data6        = self.RoundData6 
        PlayerData.Data7        = self.RoundData7 
        PlayerData.Data8        = self.RoundData8 
        PlayerData.Data9        = self.RoundData9 
        PlayerData.Data10       = self.RoundData10 
        PlayerData.Data11       = self.RoundData11  
        PlayerData.Data12       = self.RoundData12  
        PlayerData.Data13       = self.RoundData13  
        PlayerData.Data14       = self.RoundData14  
        PlayerData.Data15       = self.RoundData15 

        self.ConvertData        = ACF.RoundTypes[self.RoundType].convert
        self.BulletData         = self:ConvertData( PlayerData )

        local Efficiency        = 0.1576 * ACF.AmmoMod
        local vol               = math.floor(self:GetPhysicsObject():GetVolume())

        self.Volume = vol*Efficiency

        --ammo capacity start code
        if self.BulletData.Type ~= "Refill" then   

            --Getting entity´s dimensions
            local Min,Max = self:GetCollisionBounds()  
            local Size = (Max - Min)

            local width = (GunData.caliber)/ACF.AmmoWidthMul/1.6
            local shellLength = ((self.BulletData.PropLength or 0) + (self.BulletData.ProjLength or 0))/ACF.AmmoLengthMul/3

            --Vertical placement
            local cap1 = (math.floor(Size.z/shellLength) * math.floor(Size.x/width) * math.floor(Size.y/width)) or 1
            --Horizontal Placement 1
            local cap2 = (math.floor(Size.x/shellLength) * math.floor(Size.z/width) * math.floor(Size.y/width)) or 1
            --Horizontal placement 2
            local cap3 = (math.floor(Size.y/shellLength) * math.floor(Size.z/width) * math.floor(Size.x/width)) or 1
            --Vertical 2 piece placement
            local cap4 = math.floor(math.floor(Size.z/shellLength*2)/2 * math.floor(Size.x/width) * math.floor(Size.y/width)) or 1
            --Horizontal 2 piece  Placement 1
            local cap5 = math.floor(math.floor(Size.x/shellLength*2)/2 * math.floor(Size.z/width) * math.floor(Size.y/width)) or 1
            --Horizontal 2 piece  placement 2
            local cap6 = math.floor(math.floor(Size.y/shellLength*2)/2 * math.floor(Size.z/width) * math.floor(Size.x/width)) or 1

            local tval1 = math.max(cap1,cap2,cap3)
            local tval2 = math.max(cap4,cap5,cap6)

            if (tval2-tval1)/(tval1+tval2) > 0.3 then --2 piece ammo time, uses 2 piece if 2 piece leads to more than 30% shells
                self.Capacity = tval2
                self.IsTwoPiece = true
            else
                self.Capacity = tval1
                self.IsTwoPiece = false
            end

            self.AmmoMassMax = ((self.BulletData.ProjMass + self.BulletData.PropMass) * self.Capacity * 2) or 1 -- why *2 ?

            debugoverlay.Box(self:GetPos()+Vector(0,0,10),Vector(0,0,0), Vector(shellLength,width,width), 10, Color(255,0,0,100))
            debugoverlay.Text(self:GetPos()+Vector(0,0,15), "Bullet Dimensions", 10)

        -- for refill ammocrates Calculations 
        else 
        
            self.Capacity = 99999999
            self.AmmoMassMax = vol*1    

        -- end capacity calculations
        end 
    
        self.Caliber    = GunData.caliber or 1
        self.RoFMul     = (vol > 40250) and (1-(math.log(vol*0.00066)/math.log(2)-4)*0.05) or 1 --*0.0625 for 25% @ 4x8x8, 0.025 10%, 0.0375 15%, 0.05 20%
        self.RoFMul     = self.RoFMul + (((self.IsTwoPiece) and 0.3) or 0) --30% ROF penalty for 2 piece

        self:SetNWString( "Ammo", self.Ammo )
        self:SetNWString( "WireName", self.BulletData.Type ~= "Refill" and (GunData.name .. " Ammo") or "ACE Universal Supply Crate" )
    
        self.NetworkData = ACF.RoundTypes[self.RoundType].network
        self:NetworkData( self.BulletData )
    
        self:UpdateOverlayText()
    
    end

end

function ENT:UpdateMass()

    self.Mass = self.EmptyMass + math.Round( self.AmmoMassMax*(self.Ammo/math.max(self.Capacity,1)) )

    --reduce superflous engine calls, update crate mass every 5 kgs change or every 10s-15s
    if math.abs((self.LastMass or 0) - self.Mass) > 5 or ACF.CurTime > self.NextMassUpdate then

        self.LastMass       = self.Mass
        self.NextMassUpdate = ACF.CurTime + math.Rand(10,15)

        local phys = self:GetPhysicsObject()    
        if (phys:IsValid()) then 

            phys:SetMass( self.Mass ) 

        end
    end

end

function ENT:GetInaccuracy()
    local SpreadScale = ACF.SpreadScale
    local inaccuracy = 0
    local Gun = list.Get("ACFEnts").Guns[self.RoundId]
    
    if Gun then
        local Classes = list.Get("ACFClasses")
        inaccuracy = (Classes.GunClass[Gun.gunclass] or {spread = 0}).spread
    end
    
    local coneAng = inaccuracy * ACF.GunInaccuracyScale
    return coneAng
end

function ENT:TriggerInput( iname, value )

    if (iname == "Active") then
        if value > 0 then
            self.Active = true

            if self.Legal then
                self.Load = true
                self:FirstLoad()
            end
        else
            self.Active = false
            self.Load = false
        end
    end

end

function ENT:FirstLoad()

    for Key,Value in pairs(self.Master) do
        local Gun = self.Master[Key]
        if IsValid(Gun) and Gun.FirstLoad and Gun.BulletData.Type == "Empty" and Gun.Legal then
            Gun:LoadAmmo(false, false)
        end
    end
    
end

function ENT:Think()

    if ACF.CurTime > self.NextLegalCheck then

        self.Legal, self.LegalIssues = ACF_CheckLegal(self, self.Model, math.Round(self.EmptyMass,2), nil, true, true)
        self.NextLegalCheck = ACF.Legal.NextCheck(self.legal)
        self:UpdateOverlayText()

        if not self.Legal then
            self.Load = false
        else
            --if legal, go back to the action
            if self.Active then self.Load = true end
        end

    end

    if self.BulletData.Type == "Refill" then
        self:UpdateOverlayText()
    else
        
        self:UpdateMass()
    
        if self.Ammo ~= self.AmmoLast or not self.Legal then
            self:UpdateOverlayText()
            self.AmmoLast = self.Ammo
        end
    end

    local color = self:GetColor()
    self:SetNWVector("TracerColour", Vector( color.r, color.g, color.b ) )
    
    local cvarGrav = GetConVar("sv_gravity")
    local vec = Vector(0,0,cvarGrav:GetInt()*-1)
        
    self:SetNWVector("Accel", vec)
        
    self:NextThink( CurTime() +  self.Interval )
    
    -- cookoff handling
    if self.Damaged then
    
        local CrateType = self.BulletData.Type or "Refill"

        --If that is a refill, remove it
        if CrateType == "Refill" then
        
            self:Remove()
        
        -- immediately detonate if there's 1 or 0 shells
        elseif self.Ammo <= 1 or self.Damaged < CurTime() then 
        
            ACF_ScaledExplosion( self ) -- going to let empty crates harmlessly poot still, as an audio cue it died
            
        else
        
            if math.Rand(0,150) > self.BulletData.RoundVolume^0.5 and math.Rand(0,1) < self.Ammo/math.max(self.Capacity,1) and ACF.RoundTypes[CrateType] then
                
                self:EmitSound( "ambient/explosions/explode_4.wav", 350, math.max(255 - self.BulletData.PropMass*100,60)  ) 
                self.BulletCookSpeed    = self.BulletCookSpeed or ACF_MuzzleVelocity( self.BulletData.PropMass, self.BulletData.ProjMass/2, self.Caliber )

                self.BulletData.Pos     = self:LocalToWorld(self:OBBCenter() + VectorRand()*(self:OBBMaxs()-self:OBBMins())/2)
                self.BulletData.Flight  = (VectorRand()):GetNormalized() * self.BulletCookSpeed * 39.37 + self:GetVelocity()

                self.BulletData.Owner   = self.BulletData.Owner or self.Inflictor or self.Owner
                self.BulletData.Gun     = self.BulletData.Gun   or self
                self.BulletData.Crate   = self.BulletData.Crate or self:EntIndex()
                
                self.CreateShell        = ACF.RoundTypes[CrateType].create
                self:CreateShell( self.BulletData )
                    
                self.Ammo = self.Ammo - 1
                    
            end
                
            self:NextThink( CurTime() + self.ExplosionInterval + self.BulletData.RoundVolume^0.5/100 )
                    
        end

    -- Completely new, fresh, genius, beautiful, flawless refill system.
    elseif self.RoundType == "Refill" and self.Load then
    
        for _,Ammo in pairs( ACF.AmmoCrates ) do
        
            if Ammo.RoundType ~= "Refill" then
            
                local dist = self:GetPos():Distance(Ammo:GetPos())
                
                if dist < ACF.RefillDistance then
                
                    if Ammo.Capacity > Ammo.Ammo then
                    
                        self.SupplyingTo = self.SupplyingTo or {}
                            
                        if not table.HasValue( self.SupplyingTo, Ammo:EntIndex() ) then
                        
                            table.insert(self.SupplyingTo, Ammo:EntIndex())
                            self:RefillEffect( Ammo )
                                
                        end
                                
                        local Supply    = math.ceil((1/((Ammo.BulletData.ProjMass+Ammo.BulletData.PropMass)*5000))*self:GetPhysicsObject():GetMass()^1.2)
                        local Transfert = math.min(Supply, Ammo.Capacity - Ammo.Ammo)
                        Ammo.Ammo       = Ammo.Ammo + Transfert
                            
                        Ammo.Supplied = true
                        Ammo.Entity:EmitSound( "weapons/shotgun/shotgun_reload"..math.random(1,3)..".wav", 350, 100, 0.30 )
                        
                    end
                end
            end
        end
    end
    
    -- checks to stop supply
    if self.SupplyingTo then
        for k, EntID in pairs( self.SupplyingTo ) do
            local Ammo = ents.GetByIndex(EntID)
            if not IsValid( Ammo ) then 
                table.remove(self.SupplyingTo, k)
                self:StopRefillEffect( EntID )
            else
                local dist = self:GetPos():Distance(Ammo:GetPos())
                -- If ammo crate is out of refill max distance or is full or our refill crate is damaged or just in-active then stop refiliing it.
                if (dist > ACF.RefillDistance) or (Ammo.Capacity <= Ammo.Ammo) or self.Damaged or not self.Load or not Ammo.Legal then
                    table.remove(self.SupplyingTo, k)
                    self:StopRefillEffect( EntID )
                end
            end
        end
    end
    
    Wire_TriggerOutput(self, "Munitions", self.Ammo)
    return true

end

function ENT:RefillEffect( Target )
    umsg.Start("ACF_RefillEffect")
        umsg.Float( self:EntIndex() )
        umsg.Float( Target:EntIndex() )
        umsg.String( Target.RoundType )
    umsg.End()
end

function ENT:StopRefillEffect( TargetID )
    umsg.Start("ACF_StopRefillEffect")
        umsg.Float( self:EntIndex() )
        umsg.Float( TargetID )
    umsg.End()
end

function ENT:OnRemove()
    
    for Key,Value in pairs(self.Master) do
        if self.Master[Key] and self.Master[Key]:IsValid() then
            self.Master[Key]:Unlink( self )
            self.Ammo = 0
        end
    end
    for k,v in pairs(ACF.AmmoCrates) do
        if v == self then
            table.remove(ACF.AmmoCrates,k)
        end
    end
    
end
