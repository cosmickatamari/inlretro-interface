-- Main application flow for interacting with cartridges via USB device.
-- Refactored version that doesn't require commenting/uncommenting to change functionality.


-- Helper function that checks if a string is empty or nil.
local function isempty(s)
    return s == nil or s == ''
end

-- Wrapper for managing operations for most consoles.
function default_exec(process_opts, console_opts)
    -- Defensively filter out any console options that aren't standard.
    local default_opts = {
        rom_size_kbyte = console_opts["rom_size_kbyte"],
        wram_size_kb = console_opts["wram_size_kb"],
    }
    console_opts["console_process_script"].process(process_opts, default_opts)
end

-- Wrapper for managing Super Nintendo operations.
function snes_exec(process_opts, console_opts)
    -- Defensively filter out any console options that aren't standard.
    local snes_opts = {
        rom_size_kbyte = console_opts["rom_size_kbyte"],  
        wram_size_kb = console_opts["wram_size_kb"],
        mapper = console_opts["mapper"]
    }
    console_opts["console_process_script"].process(process_opts, console_opts)
end

-- Wrapper for managing original Gameboy operations.
function gb_exec(process_opts, console_opts)
    -- Defensively filter out any console options that aren't standard.
    local gb_opts = {
        rom_size_kbyte = console_opts["rom_size_kbyte"],  
    }
    local mappers = {
        romonly = require "scripts.gb.romonly",
        mbc1 = require "scripts.gb.mbc1",
    }
    m = mappers[console_opts["mapper"]]
    if m == nil then
        print("UNSUPPORTED MAPPER: ", console_opts["mapper"])
    else
        -- Attempt requested operations with hardware!
        -- TODO: Do plumbing for interacting with RAM.
        m.process(process_opts, console_opts)
    end
end

-- Wrapper for managing NES/Famicom operations.
function nes_exec(process_opts, console_opts)
    local dict = require "scripts.app.dict"
    local nes = require "scripts.app.nes"
    
    -- Defensively filter out any console options that are irrelevant to NES support.
    -- This will matter more when software support exists for other consoles.
    local nes_opts = {
        wram_size_kb = console_opts["wram_size_kb"],
        prg_rom_size_kb = console_opts["prg_rom_size_kb"],
        chr_rom_size_kb = console_opts["chr_rom_size_kb"],
        mirror = nil -- Used by NROM mapper only, "H" or "V".
    }

    local mappers = {
        action53_tsop = require "scripts.nes.action53_tsop",
        action53 = require "scripts.nes.action53",
        bnrom = require "scripts.nes.bnrom",
        cdream = require "scripts.nes.cdream",
        cninja = require "scripts.nes.cninja",
        cnrom = require "scripts.nes.cnrom",
        dualport = require "scripts.nes.dualport",
        easynsf = require "scripts.nes.easyNSF",
        fme7 = require "scripts.nes.fme7",
        gtrom = require "scripts.nes.gtrom",
        mapper30 = require "scripts.nes.mapper30",
        mapper30v2 = require "scripts.nes.mapper30v2",
        gxrom = require "scripts.nes.mhrom",
        mmc1 = require "scripts.nes.mmc1",
        mmc2 = require "scripts.nes.mmc2",
        mmc3 = require "scripts.nes.mmc3",
        mmc4 = require "scripts.nes.mmc4",
        mmc5 = require "scripts.nes.mmc5",
        nrom = require "scripts.nes.nrom",
        unrom = require "scripts.nes.unrom",
        unrom_tsop = require "scripts.nes.unrom_tsop",
    }

    --dict.io("IO_RESET")	
--	dict.io("NES_INIT")	
    --nes.detect_mapper_mirroring(true)
    
    m = mappers[console_opts["mapper"]]
    if m == nil then
        print("UNSUPPORTED MAPPER: ", console_opts["mapper"])
    else
        -- Attempt requested operations with hardware!

        -- TODO: Do plumbing for interacting with RAM.
        m.process(process_opts, console_opts)
    end
end

-- Point of entry from C language half of program.
function main()

    -- Globals passed in from C: 
    --  console_name:      string, name of console.
    --  mapper_name:       string, name of mapper.
    --  dump_filename:     string, filename used for writing dumped data.
    --  flash_filename:    string, filename containing data to write cartridge.
    --  verify_filename:   string, filename used for writing back data written to cartridge for verification.
    --  ramdump_filename:  string, filename used for writing dumped ram data.
    --  ramwrite_filename: string, filename containing data to write to ram on cartridge.
    --  nes_prg_rom_size_kb:    int, size of cartridge PRG-ROM in kilobytes.
    --  nes_chr_rom_size_kb:    int, size of cartridge CHR-ROM in kilobytes.
    --  nes_wram_size_kb:       int, size of cartridge WRAM in kilobytes.
    --  rom_size_kbyte:          int, size of cartridge ROM in kilobytes.

    -- TODO: This should probably be one level up.
    -- TODO: Ram probably needs a verify file as well?

    -- Print application version of the firmware for debug/support
    -- Should work on all hardware versions 
    local dict = require "scripts.app.dict"
    local help = require "scripts.app.help"
    local appver = help.hex(dict.bootload("GET_APP_VER", nil, nil, nil, true ))
    print("firmware app ver request:", appver )
    if appver < "3" then
	    print("firmware is out of date, recommend updating")
    end

--    this method only works for STM32 based devices and reads version from flash address 0x0800-0800
--    local fwupdate = require "scripts.app.fwupdate"
--    local appver = fwupdate.get_fw_appver(true)
--    if appver ~= "AV03" then
--	    print("new firmware has been released, recommend upgrading")
--    end

    -- Always test!
    local do_test = true
    
    -- If a dump filename was provided, dump data from cartridge to a file.
    local do_read = not isempty(dump_filename)
    
    -- If a flash filename was provided, write its contents to the cartridge.
    -- TODO: Check for erase + dump at same time, not permitted.
    local do_erase = not isempty(flash_filename)
    -- If writing, always erase.
    -- TODO: Check for program and dump at same time, not permitted.
    local do_program = do_erase
    
    -- If a verify_filename was provided, dump data from cartridge after flash to a file.
    local do_verify = not isempty(verify_filename)

    local do_dumpram = not isempty(ramdump_filename)
    local do_writeram = not isempty(ramwrite_filename)

    -- Pack main process state into table.
    local process_opts = {
        test = do_test,
        read = do_read,
        dump_filename = dump_filename,
        erase = do_erase,
        program = do_program,
        flash_filename = flash_filename,
        verify = do_verify,
        verify_filename = verify_filename,
        dumpram = do_dumpram,
        dumpram_filename = ramdump_filename,
        writeram = do_writeram,
        writeram_filename = ramwrite_filename,
    }

    local consoles = {
        dmg = gb_exec,
        gb = gb_exec, -- Support two names for gameboy
        gba = default_exec,
        genesis = default_exec,
        n64 = default_exec,
        nes = nes_exec,
        snes = snes_exec,
    }
    local console_scripts = {
        n64 = require "scripts.n64.basic",
        nes = require "scripts.app.nes",
        gba = require "scripts.gba.basic",
        genesis = require "scripts.sega.genesis_v1",
        --genesis = require "scripts.sega.genesis_v2",
        snes = require "scripts.snes.v2proto_hirom"
        --snes = require "scripts.snes.v2manual_hirom"
    }
    local console_exec = consoles[console_name]
    local console_process_script = console_scripts[console_name]
    if console_exec == nil then 
        print("UNSUPPORTED CONSOLE: ", console_name)
    else
        local console_opts = {
            wram_size_kb = nes_wram_size_kb,
            prg_rom_size_kb = nes_prg_rom_size_kb,
            chr_rom_size_kb = nes_chr_rom_size_kb,
            rom_size_kbyte = rom_size_kbyte,
            console_process_script = console_process_script,
            mapper = mapper_name,
        }
        console_exec(process_opts, console_opts)
    end
end

-- Don't do this. Next iteration will call a function, not the whole script.
main()
