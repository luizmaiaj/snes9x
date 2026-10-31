/*****************************************************************************\
     Snes9x - Portable Super Nintendo Entertainment System (TM) emulator.
                This file is licensed under the Snes9x License.
   For further information, consult the LICENSE file in the root directory.
\*****************************************************************************/

/***********************************************************************************
  SNES9X for Mac OS (c) Copyright John Stiles

  Snes9x for Mac OS X

  (c) Copyright 2001 - 2011  zones
  (c) Copyright 2002 - 2005  107
  (c) Copyright 2002         PB1400c
  (c) Copyright 2004         Alexander and Sander
  (c) Copyright 2004 - 2005  Steven Seeger
  (c) Copyright 2005         Ryan Vogt
  (c) Copyright 2019         Michael Donald Buckley
 ***********************************************************************************/


#include "snes9x.h"
#include "memmap.h"
#include "apu.h"
#include "snapshot.h"
#include "cheats.h"
#include "movie.h"
#include "display.h"
#include "jma/s9x-jma.h"

#include <vector>
#include <wchar.h>

#include "mac-prefix.h"
#include "mac-audio.h"
#include "mac-cart.h"
#include "mac-dialog.h"
#include "mac-file.h"
#include "mac-os.h"
#include "mac-screenshot.h"
#include "mac-stringtools.h"
#include "mac-snes9x.h"

extern wchar_t  macRecordWChar[MOVIE_MAX_METADATA];

bool8 LoadZip (const char *, uint32 *, uint8 *, uint32);


void SNES9X_Go (void)
{
	if (cartOpen)
		running = true;
}

// Whether the 0x40 bytes at offset are a ROM's header: its checksum and complement
// match or, as homebrew and hacks often leave those wrong, its other fields are sane.
static bool HasROMHeader (const uint8 *rom, uint32 size, uint32 offset)
{
	if (offset + 0x40 > size)
		return (false);

	const uint8	*header = rom + offset;
	uint16		complement = header[0x1c] | (header[0x1d] << 8);
	uint16		checksum   = header[0x1e] | (header[0x1f] << 8);
	uint16		reset      = header[0x3c] | (header[0x3d] << 8);
	uint8		mapMode    = header[0x15];
	uint8		romSize    = header[0x17];

	if (complement + checksum == 0xffff && complement != 0 && checksum != 0)
		return (true);

	return (reset >= 0x8000 && (mapMode & 0xe0) == 0x20 && romSize >= 5 && romSize <= 13);
}

// Reads a ROM file the way CMemory::FileLoader does, but into buffer: FileLoader
// would change the filename the running game saves under.
static uint32 ReadROMFile (NSURL *fileURL, uint8 *buffer, uint32 size)
{
	const char	*filename = fileURL.path.UTF8String;
	NSString	*extension = fileURL.pathExtension.lowercaseString;

	if ([extension isEqualToString:@"zip"] || [extension isEqualToString:@"msu1"])
	{
		uint32	zipSize = 0;

		return (LoadZip(filename, &zipSize, buffer, size) ? zipSize : 0);
	}

	if ([extension isEqualToString:@"jma"])
		return ((uint32) load_jma_file(filename, buffer));

	STREAM	fp = OPEN_STREAM(filename, "rb");
	if (!fp)
		return (0);

	uint32	fileSize = READ_STREAM(buffer, size, fp);
	CLOSE_STREAM(fp);

	return (fileSize);
}

bool8 SNES9X_LooksLikeROM (NSURL *fileURL)
{
	// LoROM, HiROM, ExLoROM and ExHiROM.
	const uint32	headerOffsets[] = { 0x7fc0, 0xffc0, 0x407fc0, 0x40ffc0 };
	const uint32	copierHeaderSize = 0x200;
	const uint32	bufferSize = CMemory::MAX_ROM_SIZE + copierHeaderSize;

	std::vector<uint8>	buffer(bufferSize);
	uint32				size = ReadROMFile(fileURL, buffer.data(), bufferSize);

	for (uint32 offset : headerOffsets)
	{
		if (HasROMHeader(buffer.data(), size, offset) ||
			HasROMHeader(buffer.data(), size, offset + copierHeaderSize))
			return (TRUE);
	}

	return (FALSE);
}

// The core's is_BSCart_BIOS, which can't run here: it sets Memory.LoROM and HiROM,
// and the running game still needs them.
static bool IsBSCart (const uint8 *data, uint32 size)
{
	return ((size > 0x7fda && data[0x7fb2] == 0x5a && data[0x7fb5] != 0x20 && data[0x7fda] == 0x33) ||
			(size > 0xffda && data[0xffb2] == 0x5a && data[0xffb5] != 0x20 && data[0xffda] == 0x33));
}

static bool IsSufamiTurboCart (const uint8 *data, uint32 size)
{
	return (size >= 0x80000 && size <= 0x100000 &&
			strncmp((const char *) data, "BANDAI SFC-ADX", 14) == 0 &&
			strncmp((const char *) (data + 0x10), "SFC-ADX BACKUP", 14) != 0);
}

static bool HasSufamiTurboBIOS (NSURL *biosFolderURL)
{
	NSData		*bios = [NSData dataWithContentsOfURL:[biosFolderURL URLByAppendingPathComponent:@"STBIOS.bin"]];
	const char	*data = (const char *) bios.bytes;

	return (bios.length >= 0x40000 &&
			strncmp(data, "BANDAI SFC-ADX", 14) == 0 &&
			strncmp(data + 0x10, "SFC-ADX BACKUP", 14) == 0);
}

NSURL * SNES9X_BIOSFolder (NSURL *cartURL)
{
	// Beside the ROM, the core's folder follows Memory.ROMFilename: that names
	// the cart once it loads, but still the running game here.
	if (saveInROMFolder == 1)
		return (cartURL.URLByDeletingLastPathComponent);

	return ([NSURL fileURLWithPath:@(S9xGetDirectory(BIOS_DIR).c_str()) isDirectory:YES]);
}

// The first cart decides, as in CMemory::LoadMultiCartInt: the core drops a
// second cart it can't use.
NSInteger SNES9X_MultiCartProblem (NSURL *cartURL, NSURL *biosFolderURL)
{
	const uint32	copierHeaderSize = 0x200;
	const uint32	bufferSize = CMemory::MAX_ROM_SIZE + copierHeaderSize;

	std::vector<uint8>	buffer(bufferSize);
	uint32				size = ReadROMFile(cartURL, buffer.data(), bufferSize);
	const uint8			*data = buffer.data();

	if ((size % 0x2000 == copierHeaderSize && headerDetect != kNoHeaderForce) ||
		(size >= copierHeaderSize && headerDetect == kHeaderForce))
	{
		data += copierHeaderSize;
		size -= copierHeaderSize;
	}

	if (IsSufamiTurboCart(data, size))
		return (HasSufamiTurboBIOS(biosFolderURL) ? S9xMultiCartProblemNone : S9xMultiCartProblemNoBIOS);

	return (IsBSCart(data, size) ? S9xMultiCartProblemNone : S9xMultiCartProblemNotACart);
}

bool8 SNES9X_OpenCart (NSURL *inRef)
{
	NSURL		*cartRef;
	const char	*filename = inRef.path.UTF8String;

	if (cartOpen)
	{
		SNES9X_SaveSRAM();
		S9xResetSaveTimer(false);
		S9xSaveCheatFile(S9xGetFilename(".cht", CHEAT_DIR));
	}

	if (!inRef)
	{
        cartRef = NavOpenROMImage();
		if (!cartRef)
		{
			cartOpen = false;
			return (false);
		}
	}
	else
		cartRef = inRef;

	spcFileCount = pngFileCount = 0;

	CheckSaveFolder(cartRef);

	Settings.ForceLoROM          = (romDetect        == kLoROMForce       );
	Settings.ForceHiROM          = (romDetect        == kHiROMForce       );
	Settings.ForceHeader         = (headerDetect     == kHeaderForce      );
	Settings.ForceNoHeader       = (headerDetect     == kNoHeaderForce    );
	Settings.ForceInterleaved    = (interleaveDetect == kInterleaveForce  );
	Settings.ForceInterleaved2   = (interleaveDetect == kInterleave2Force );
	Settings.ForceInterleaveGD24 = (interleaveDetect == kInterleaveGD24   );
	Settings.ForceNotInterleaved = (interleaveDetect == kNoInterleaveForce);
	Settings.ForcePAL            = (videoDetect      == kPALForce         );
	Settings.ForceNTSC           = (videoDetect      == kNTSCForce        );

	GFX.InfoString = "";
	GFX.InfoStringTimeout = 0;

	S9xResetSaveTimer(true);

	SNES9X_InitSound();

	if (Memory.LoadROM(filename))
	{
		cartOpen = true;

		SNES9X_LoadSRAM();

		ChangeTypeAndCreator(filename, 'CART', '~9X~');

		ApplyNSRTHeaderControllers();

		for (int a = 0; a < MAC_MAX_PLAYERS; a++)
			for (int b = 0; b < 12; b++)
				autofireRec[a].nextTime[b] = 0;

		return (true);
	}
	else
	{
		cartOpen = false;
		return (false);
	}
}

bool8 SNES9X_OpenMultiCart (NSURL *cart1FileURL, NSURL *cart2FileURL)
{
	Boolean	r;

	if (cartOpen)
	{
		SNES9X_SaveSRAM();
		S9xResetSaveTimer(false);
		S9xSaveCheatFile(S9xGetFilename(".cht", CHEAT_DIR));
	}

	spcFileCount = pngFileCount = 0;

	Settings.ForceHeader   = (headerDetect     == kHeaderForce  );
	Settings.ForceNoHeader = (headerDetect     == kNoHeaderForce);
	Settings.ForcePAL      = (videoDetect      == kPALForce     );
	Settings.ForceNTSC     = (videoDetect      == kNTSCForce    );

	GFX.InfoString = "";
	GFX.InfoStringTimeout = 0;

	S9xResetSaveTimer(true);

	SNES9X_InitSound();

	if (Memory.LoadMultiCart(cart1FileURL.path.UTF8String, cart2FileURL.path.UTF8String))
	{
		cartOpen = true;

		SNES9X_LoadSRAM();

		ChangeTypeAndCreator(cart1FileURL.path.UTF8String, 'CART', '~9X~');

		if (cart2FileURL != nil)
		{
			ChangeTypeAndCreator(cart2FileURL.path.UTF8String, 'CART', '~9X~');
		}

		ApplyNSRTHeaderControllers();

		for (int a = 0; a < MAC_MAX_PLAYERS; a++)
			for (int b = 0; b < 12; b++)
				autofireRec[a].nextTime[b] = 0;

		return (true);
	}
	else
	{
		cartOpen = false;
		return (false);
	}
}

void SNES9X_LoadSRAM (void)
{
	if (cartOpen)
		Memory.LoadSRAM(S9xGetFilename(".srm", SRAM_DIR).c_str());
}

void SNES9X_SaveSRAM (void)
{
	std::string	sramFilename;

	if (cartOpen)
	{
		sramFilename = S9xGetFilename(".srm", SRAM_DIR);
		Memory.SaveSRAM(sramFilename.c_str());
		ChangeTypeAndCreator(sramFilename.c_str(), 'SRAM', '~9X~');
	}
}

void SNES9X_Reset (void)
{
	if (cartOpen)
	{
		SNES9X_SaveSRAM();
		S9xReset();
		SNES9X_LoadSRAM();
	}
}

void SNES9X_SoftReset (void)
{
	if (cartOpen)
	{
		SNES9X_SaveSRAM();
		S9xSoftReset();
		SNES9X_LoadSRAM();
	}
}

bool8 SNES9X_Freeze (void)
{
	int			which;
    const char	*filename;

	if (cartOpen)
	{
		MacStopSound();

		which = PromptFreezeDefrost(true);

		if (which >= 0)
		{
			filename = S9xGetFreezeFilename(which);

            unlink(filename);

			S9xFreezeGame(filename);
			ChangeTypeAndCreator(filename, 'SAVE', '~9X~');
            WriteThumbnailToExtendedAttribute(filename, 128, 120);

			SNES9X_Go();

			MacStartSound();
			return (true);
		}
		else
		{
			MacStartSound();
			return (false);
		}
	}
	else
		return (false);
}

bool8 SNES9X_Defrost (void)
{
	int			which;
	const char	*filename;

	if (cartOpen)
	{
		MacStopSound();

		which = PromptFreezeDefrost(false);

		if (which >= 0)
		{
			filename = S9xGetFreezeFilename(which);
			S9xUnfreezeGame(filename);

			SNES9X_Go();

			MacStartSound();
			return (true);
		}
		else
		{
			MacStartSound();
			return (false);
		}
	}
	else
		return (false);
}

bool8 SNES9X_FreezeTo (void)
{
	if (cartOpen)
	{
		NSURL *url = NavFreezeTo();
		if (url != nil)
		{
			const char *filename = url.path.UTF8String;
            unlink(filename);

			S9xFreezeGame(filename);
			ChangeTypeAndCreator(filename, 'SAVE', '~9X~');;
            WriteThumbnailToExtendedAttribute(filename, 128, 120);

			return (true);
		}
	}

	return (false);
}

bool8 SNES9X_DefrostFrom (void)
{
	if (cartOpen)
	{
		NSURL *url = NavDefrostFrom();
		if (url != nil)
		{
			const char *filename = url.path.UTF8String;
			S9xUnfreezeGame(filename);

			SNES9X_Go();

			return (true);
		}
	}

	return (false);
}

bool8 SNES9X_RecordMovie (void)
{
	if (cartOpen)
	{
		NSURL *url = NavRecordMovieTo();
		if (url != nil)
		{
			const char *filename = url.path.UTF8String;
            unlink(filename);

			int		r;
			uint8   opt = 0, mask = 0;

			for (int i = 0; i <= 4; i++)
				if (macRecordFlag & (1 << i))
					mask |= (1 << i);

			if (macRecordFlag & (1 << 5))
				opt |= MOVIE_OPT_FROM_RESET;
			else
				opt |= MOVIE_OPT_FROM_SNAPSHOT;

			r = S9xMovieCreate(filename, mask, opt, macRecordWChar, (int)wcslen(macRecordWChar));
			if (r == SUCCESS)
			{
				ChangeTypeAndCreator(filename, 'SMOV', '~9X~');

				if ((macRecordFlag & (1 << 5)) == 0)
				{
                    WriteThumbnailToExtendedAttribute(filename, 128, 120);
				}

				SNES9X_Go();

				return (true);
			}
		}
	}

	return (false);
}

bool8 SNES9X_PlayMovie (void)
{
	if (cartOpen)
	{
		NSURL *url = NavPlayMovieFrom();
		if (url != nil)
		{
			const char *filename = url.path.UTF8String;
			int r;

			r = S9xMovieOpen(filename, macPlayFlag & 1);
			if (r == SUCCESS)
			{
				SNES9X_Go();

				return (true);
			}
		}
	}

	return (false);
}

bool8 SNES9X_QTMovieRecord (void)
{
	if (cartOpen)
	{
		NSURL *url = NavQTMovieRecordTo();
		if (url != nil)
		{
			macQTRecord = true;
			SNES9X_Go();

			return (true);
		}
	}

	macQTRecord = false;

	return (false);
}

void SNES9X_Quit (void)
{
	if (cartOpen)
	{
		SNES9X_SaveSRAM();
		S9xResetSaveTimer(false);
		S9xSaveCheatFile(S9xGetFilename(".cht", CHEAT_DIR));
	}
}

void SNES9X_InitSound (void)
{
	S9xInitSound(0);
}
