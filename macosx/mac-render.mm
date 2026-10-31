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

#import <Cocoa/Cocoa.h>

#include "snes9x.h"
#include "cheats.h"
#include "memmap.h"
#include "apu.h"
#include "display.h"
#include "blit.h"

#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <fcntl.h>
#include <unistd.h>
#include <atomic>

#include "mac-prefix.h"
#include "mac-keyboard.h"
#include "mac-os.h"
#include "mac-screenshot.h"
#include "mac-render.h"

static void S9xInitMetal (void);
static void S9xDeinitMetal(void);
static void S9xPutImageMetal (int, int, uint16 *);

static int					whichBuf          = 0;
static int					textureNum        = 0;
static int					prevBlitWidth, prevBlitHeight;
static int					imageWidth[2], imageHeight[2];
static int					nx                = 2;

typedef struct
{
    vector_float2 position;
    vector_float2 textureCoordinate;
} MetalVertex;

@interface MetalLayerDelegate: NSObject<CALayerDelegate, NSViewLayerContentScaleDelegate>
@end

@implementation MetalLayerDelegate
- (BOOL)layer:(CALayer *)layer shouldInheritContentsScale:(CGFloat)newScale fromWindow:(NSWindow *)window
{
	return YES;
}

@end

S9xFrameChannel				*secondGameChannel = nil;
bool8						gameMuted = false;

// Two frames, so the window can read one while the game writes the other.
struct SharedFrames
{
	std::atomic<uint32>	sequence;	// Frames published so far; its low bit picks the newest.
	std::atomic<uint32>	gamepadButtons;					// One bit per S9xButtonCode.
	std::atomic<uint32>	keyButtons[MAC_MAX_PLAYERS];	// The same, per player.
	std::atomic<uint32>	rawKeys[MAC_NUM_KEYCODES / 32 + 1];
	std::atomic<uint32>	requests;						// S9xSecondGameRequest bits.
	std::atomic<uint32>	soundOn;
	std::atomic<uint32>	paused;
	std::atomic<uint32>	choosingSlot;
	int32				width[2];
	int32				height[2];
	uint8				pixels[2][MAX_SNES_WIDTH * MAX_SNES_HEIGHT * 4];
};

static_assert(ATOMIC_INT_LOCK_FREE == 2, "the two processes can't share a lock");
static_assert(kNumButtons <= 32, "buttons travel as bits of a 32-bit value");

@implementation S9xFrameChannel
{
	SharedFrames	*frames;
	uint32			lastRead;
	BOOL			created;
}

- (instancetype)initWithName:(NSString *)name descriptor:(int)descriptor created:(BOOL)didCreate
{
	struct stat info;

	if (descriptor < 0)
	{
		return nil;
	}

	void *memory = MAP_FAILED;

	if (fstat(descriptor, &info) == 0 && info.st_size >= (off_t) sizeof(SharedFrames))
	{
		memory = mmap(NULL, sizeof(SharedFrames), PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
	}

	close(descriptor);

	if (memory == MAP_FAILED)
	{
		if (didCreate)
		{
			shm_unlink(name.UTF8String);
		}

		return nil;
	}

	if (self = [super init])
	{
		_name = [name copy];
		frames = (SharedFrames *) memory;
		created = didCreate;
	}

	return self;
}

+ (S9xFrameChannel *)createChannel
{
	static std::atomic<int> count(0);

	// shm_open names can't pass PSHMNAMLEN, 31 characters.
	NSString *name = [NSString stringWithFormat:@"/s9x-%d-%d", getpid(), ++count];
	int descriptor = shm_open(name.UTF8String, O_RDWR | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR);

	if (descriptor < 0)
	{
		return nil;
	}

	if (ftruncate(descriptor, sizeof(SharedFrames)) != 0)
	{
		close(descriptor);
		shm_unlink(name.UTF8String);
		return nil;
	}

	return [[S9xFrameChannel alloc] initWithName:name descriptor:descriptor created:YES];
}

+ (S9xFrameChannel *)openChannelWithName:(NSString *)name
{
	return [[S9xFrameChannel alloc] initWithName:name descriptor:shm_open(name.UTF8String, O_RDWR) created:NO];
}

- (void)dealloc
{
	munmap(frames, sizeof(SharedFrames));

	if (created)
	{
		shm_unlink(_name.UTF8String);
	}
}

- (BOOL)writeFrame:(const void *)rgba width:(int)width height:(int)height
{
	if (width <= 0 || height <= 0 || width > MAX_SNES_WIDTH || height > MAX_SNES_HEIGHT)
	{
		return NO;
	}

	uint32 next = frames->sequence.load(std::memory_order_relaxed) + 1;
	uint32 slot = next & 1;

	frames->width[slot] = width;
	frames->height[slot] = height;
	memcpy(frames->pixels[slot], rgba, width * height * 4);
	frames->sequence.store(next, std::memory_order_release);

	return YES;
}

- (CGImageRef)copyNewestImage
{
	// The game may lap this read; a retry gets the frame after it.
	for (int attempt = 0; attempt < 3; attempt++)
	{
		uint32 sequence = frames->sequence.load(std::memory_order_acquire);

		if (sequence == 0 || sequence == lastRead)
		{
			return NULL;
		}

		uint32 slot = sequence & 1;
		int32 width = frames->width[slot];
		int32 height = frames->height[slot];

		// The other process wrote these, so don't trust them.
		if (width <= 0 || height <= 0 || width > MAX_SNES_WIDTH || height > MAX_SNES_HEIGHT)
		{
			return NULL;
		}

		NSData *pixels = [NSData dataWithBytes:frames->pixels[slot] length:width * height * 4];

		std::atomic_thread_fence(std::memory_order_acquire);

		if (frames->sequence.load(std::memory_order_relaxed) != sequence)
		{
			continue;
		}

		lastRead = sequence;

		CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef) pixels);
		CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
		CGImageRef image = CGImageCreate(width, height, 8, 32, width * 4, colorSpace,
										 kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault,
										 provider, NULL, false, kCGRenderingIntentDefault);

		CGColorSpaceRelease(colorSpace);
		CGDataProviderRelease(provider);

		return image;
	}

	return NULL;
}

- (BOOL)isMuted
{
	return frames->soundOn.load() == 0;
}

- (void)setMuted:(BOOL)muted
{
	frames->soundOn.store(muted ? 0 : 1);
}

- (BOOL)isPaused
{
	return frames->paused.load() != 0;
}

- (void)setPaused:(BOOL)paused
{
	frames->paused.store(paused ? 1 : 0);
}

- (BOOL)isChoosingSlot
{
	return frames->choosingSlot.load() != 0;
}

- (void)setChoosingSlot:(BOOL)choosingSlot
{
	frames->choosingSlot.store(choosingSlot ? 1 : 0);
}

static void SetBit(std::atomic<uint32> *bits, int bit, BOOL on)
{
	if (on)
	{
		bits[bit / 32].fetch_or(1u << (bit % 32));
	}
	else
	{
		bits[bit / 32].fetch_and(~(1u << (bit % 32)));
	}
}

- (void)setGamepadButton:(int)button pressed:(BOOL)pressed
{
	if (button >= 0 && button < kNumButtons)
	{
		SetBit(&frames->gamepadButtons, button, pressed);
	}
}

- (void)setKeyButton:(int)button player:(int)player pressed:(BOOL)pressed
{
	if (button >= 0 && button < kNumButtons && player >= 0 && player < MAC_MAX_PLAYERS)
	{
		SetBit(&frames->keyButtons[player], button, pressed);
	}
}

- (void)setRawKey:(int)keyCode pressed:(BOOL)pressed
{
	if (keyCode >= 0 && keyCode < MAC_NUM_KEYCODES)
	{
		SetBit(frames->rawKeys, keyCode, pressed);
	}
}

- (void)releaseGamepad
{
	frames->gamepadButtons.store(0);
}

- (void)releaseKeyboard
{
	for (auto &buttons : frames->keyButtons)
	{
		buttons.store(0);
	}

	for (auto &keys : frames->rawKeys)
	{
		keys.store(0);
	}
}

- (void)addKeys:(bool8 [MAC_MAX_PLAYERS][kNumButtons])keys gamepadButtons:(bool8 [MAC_MAX_PLAYERS][kNumButtons])gamepadButtons
{
	uint32 pad = frames->gamepadButtons.load();

	for (int button = 0; button < kNumButtons; button++)
	{
		// The second game has one player, on the window's Player 1 mapping.
		gamepadButtons[0][button] |= (pad >> button) & 1;

		for (int player = 0; player < MAC_MAX_PLAYERS; player++)
		{
			keys[player][button] |= (frames->keyButtons[player].load() >> button) & 1;
		}
	}
}

- (void)copyRawKeys:(bool8 *)rawKeys
{
	for (int key = 0; key < MAC_NUM_KEYCODES; key++)
	{
		rawKeys[key] = (frames->rawKeys[key / 32].load() >> (key % 32)) & 1;
	}
}

- (void)addRequest:(S9xSecondGameRequest)request
{
	frames->requests.fetch_or(request);
}

- (S9xSecondGameRequest)takeRequests
{
	return frames->requests.exchange(0);
}

@end

CAMetalLayer    			*metalLayer = nil;
MetalLayerDelegate			*layerDelegate = nil;
id<MTLDevice>   			metalDevice = nil;
id<MTLTexture>  			metalTexture = nil;
id<MTLCommandQueue>			metalCommandQueue = nil;
id<MTLRenderPipelineState>	metalPipelineState = nil;

void InitGraphics (void)
{
	if (!S9xBlitFilterInit()      |
		!S9xBlit2xSaIFilterInit() |
		!S9xBlitHQ2xFilterInit()  |
		!S9xBlitNTSCFilterInit())
		QuitWithFatalError(@"render 02");

	switch (videoMode)
	{
		default:
		case VIDEOMODE_NTSC_C:
		case VIDEOMODE_NTSC_TV_C:
			S9xBlitNTSCFilterSet(&snes_ntsc_composite);
			break; 

		case VIDEOMODE_NTSC_S:
		case VIDEOMODE_NTSC_TV_S:
			S9xBlitNTSCFilterSet(&snes_ntsc_svideo);
			break; 

		case VIDEOMODE_NTSC_R:
		case VIDEOMODE_NTSC_TV_R:
			S9xBlitNTSCFilterSet(&snes_ntsc_rgb);
			break; 

		case VIDEOMODE_NTSC_M:
		case VIDEOMODE_NTSC_TV_M:
			S9xBlitNTSCFilterSet(&snes_ntsc_monochrome);
			break;
	}
}

void DeinitGraphics (void)
{
	S9xBlitNTSCFilterDeinit();
	S9xBlitHQ2xFilterDeinit();
	S9xBlit2xSaIFilterDeinit();
	S9xBlitFilterDeinit();
}

void DrawFreezeDefrostScreen (uint8 *draw)
{
	const int w = SNES_WIDTH << 1, h = SNES_HEIGHT << 1;
	S9xPutImageMetal(w, h, (uint16 *)draw);
}

static void S9xInitMetal (void)
{
    glScreenW = glScreenBounds.size.width;
    glScreenH = glScreenBounds.size.height;

    metalLayer = (CAMetalLayer *)s9xView.layer;
	layerDelegate = [MetalLayerDelegate new];
	metalLayer.delegate = layerDelegate;
	
    metalDevice = s9xView.device;
			
	metalCommandQueue = [metalDevice newCommandQueue];
	
	NSError *error = nil;
	id<MTLLibrary> defaultLibrary = [metalDevice newDefaultLibraryWithBundle:[NSBundle bundleForClass:[S9xEngine class]] error:&error];

	MTLRenderPipelineDescriptor *pipelineDescriptor = [MTLRenderPipelineDescriptor new];
	pipelineDescriptor.label = @"Snes9x Pipeline";
	pipelineDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
	pipelineDescriptor.colorAttachments[0].pixelFormat = s9xView.colorPixelFormat;
	pipelineDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];
	
	metalPipelineState = [metalDevice newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
	
	if (metalPipelineState == nil)
	{
		NSLog(@"%@",error);
	}
}

static void S9xDeinitMetal (void)
{
	
	metalCommandQueue = nil;
	metalDevice = nil;
	metalTexture = nil;
	metalLayer = nil;
}

void GetGameDisplay (int *w, int *h)
{
	if (w != NULL && h != NULL)
	{
        *w = s9xView.frame.size.width;
		*h = s9xView.frame.size.height;
	}
}

void S9xInitDisplay (int argc, char **argv)
{
    glScreenBounds = s9xView.frame;

	unlimitedCursor = CGPointMake(0.0f, 0.0f);

	imageWidth[0] = imageHeight[0] = 0;
	imageWidth[1] = imageHeight[1] = 0;
	prevBlitWidth = prevBlitHeight = 0;
	whichBuf      = 0;
	textureNum    = 0;

	switch (videoMode)
	{
		case VIDEOMODE_HQ4X:
			nx =  4;
			break;

		case VIDEOMODE_HQ3X:
			nx =  3;
			break;

		case VIDEOMODE_NTSC_C:
		case VIDEOMODE_NTSC_S:
		case VIDEOMODE_NTSC_R:
		case VIDEOMODE_NTSC_M:
			nx = -1;
			break;

		case VIDEOMODE_NTSC_TV_C:
		case VIDEOMODE_NTSC_TV_S:
		case VIDEOMODE_NTSC_TV_R:
		case VIDEOMODE_NTSC_TV_M:
			nx = -2;
			break;

		default:
			nx =  2;
			break;
	}

    S9xInitMetal();

	S9xSetSoundMute(gameMuted);
    lastFrame = GetMicroseconds();
}

void S9xDeinitDisplay (void)
{
	S9xSetSoundMute(true);
    S9xDeinitMetal();
}

bool8 S9xInitUpdate (void)
{
	return (true);
}

bool8 S9xDeinitUpdate (int width, int height)
{
	S9xPutImage(width, height);
	return true;
}

bool8 S9xContinueUpdate (int width, int height)
{
	return (true);
}

void S9xPutImage (int width, int height)
{
	for(unsigned int i = 0 ; i < sizeof(watches)/sizeof(*watches) ; i++)
	{
		if(watches[i].on)
		{
			int address = watches[i].address - 0x7E0000;
			const uint8* source;

			if(address < 0x20000)
			{
				source = Memory.RAM + address;
			}
			else if(address < 0x30000)
			{
				source = Memory.SRAM + address - 0x20000;
			}
			else
			{
				source = Memory.FillRAM + address - 0x30000;
			}

			memcpy(&(Cheat.CWatchRAM[address]), source, watches[i].size);
		}
	}

    if (Settings.DisplayFrameRate)
    {
        static int	drawnFrames[60] = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
                                        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 };
        static int	tableIndex = 0;
        int			frameCalc  = 0;

        drawnFrames[tableIndex] = skipFrames;

        if (Settings.TurboMode)
        {
            drawnFrames[tableIndex] = (drawnFrames[tableIndex] + (macFastForwardRate / 2)) / macFastForwardRate;
            if (drawnFrames[tableIndex] == 0)
                drawnFrames[tableIndex] = 1;
        }

        tableIndex = (tableIndex + 1) % 60;

        for (int i = 0; i < 60; i++)
            frameCalc += drawnFrames[i];

		// avoid dividing by 0
		if (frameCalc == 0)
			frameCalc = 1;
		
        IPPU.DisplayedRenderedFrameCount = (Memory.ROMFramesPerSecond * 60) / frameCalc;
    }
	
	S9xPutImageMetal(width, height, GFX.Screen);
}


static void S9xPutImageMetal (int width, int height, uint16 *buffer16)
{
	static uint8 *buffer = nil;
	static int buffer_size = 0;

	if (buffer_size != width * height * 4)
	{
		buffer = (uint8 *)realloc(buffer, width * height * 4);
		buffer_size = width * height * 4;
	}

	for (int y = 0; y < height; y++)
	{
		for (int x = 0; x < width; x++)
		{
			uint16 pixel = buffer16[y * GFX.RealPPL + x];
			unsigned int red = (pixel & FIRST_COLOR_MASK_RGB555) >> 10;
			unsigned int green = (pixel & SECOND_COLOR_MASK_RGB555) >> 5;
			unsigned int blue = (pixel & THIRD_COLOR_MASK_RGB555);

			red = ( red * 527 + 23 ) >> 6;
			green = ( green * 527 + 23 ) >> 6;
			blue = ( blue * 527 + 23 ) >> 6;

			int offset = (y * width + x) * 4;
			buffer[offset++] = (uint8)red;
			buffer[offset++] = (uint8)green;
			buffer[offset++] = (uint8)blue;
			buffer[offset] = 0xFF;
		}
	}
	
	if (secondGameChannel != nil)
	{
		[secondGameChannel writeFrame:buffer width:width height:height];
		return;
	}

	CGSize layerSize = metalLayer.bounds.size;
	
	@autoreleasepool {
		MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor new];
		textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
		textureDescriptor.width = width;
		textureDescriptor.height = height;
		
		metalTexture = [metalDevice newTextureWithDescriptor:textureDescriptor];
		
		[metalTexture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:buffer bytesPerRow:width * 4];
		
		float vWidth = layerSize.width / 2.0;
		float vHeight = layerSize.height / 2.0;
		
		const MetalVertex verticies[] =
		{
			// Pixel positions, Texture coordinates
			{ {  vWidth,  -vHeight },  { 1.f, 1.f } },
			{ { -vWidth,  -vHeight },  { 0.f, 1.f } },
			{ { -vWidth,   vHeight },  { 0.f, 0.f } },
			
			{ {  vWidth,  -vHeight },  { 1.f, 1.f } },
			{ { -vWidth,   vHeight },  { 0.f, 0.f } },
			{ {  vWidth,   vHeight },  { 1.f, 0.f } },
		};
		
		id<MTLBuffer> vertexBuffer = [metalDevice newBufferWithBytes:verticies length:sizeof(verticies) options:MTLResourceStorageModeShared];
		id<MTLBuffer> fragmentBuffer = [metalDevice newBufferWithBytes:&videoMode length:sizeof(videoMode) options:MTLResourceStorageModeShared];
		
		id<MTLCommandBuffer> commandBuffer = [metalCommandQueue commandBuffer];
		commandBuffer.label = @"Snes9x command buffer";
		
		id<CAMetalDrawable> drawable = [metalLayer nextDrawable];
		
		MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
		
		renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
		renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
		renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0,0.0,0.0,1.0);
		
		if(renderPassDescriptor != nil)
		{
			id<MTLRenderCommandEncoder> renderEncoder =
			[commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
			renderEncoder.label = @"Snes9x render encoder";
			
			vector_uint2 viewportSize = { static_cast<unsigned int>(layerSize.width), static_cast<unsigned int>(layerSize.height) };
			
			CGFloat scale = metalLayer.contentsScale;
			[renderEncoder setViewport:(MTLViewport){0.0, 0.0, layerSize.width * scale, layerSize.height * scale, -1.0, 1.0 }];
			
			[renderEncoder setRenderPipelineState:metalPipelineState];
			
			[renderEncoder setVertexBuffer:vertexBuffer
									offset:0
								   atIndex:0];
			
			[renderEncoder setVertexBytes:&viewportSize
								   length:sizeof(viewportSize)
								  atIndex:1];
			
			[renderEncoder setFragmentTexture:metalTexture atIndex:0];
			[renderEncoder setFragmentBuffer:fragmentBuffer offset:0 atIndex:1];
			
			[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
			
			[renderEncoder endEncoding];
			
			[commandBuffer commit];
			
			[commandBuffer waitUntilCompleted];
			
			[drawable present];
		}
	}
}

void S9xTextMode (void)
{
	return;
}

void S9xGraphicsMode (void)
{
	return;
}
