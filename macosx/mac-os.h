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


#ifndef _mac_os_h_
#define _mac_os_h_

#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>

#import <os/lock.h>

#import "mac-controls.h"

enum
{
	SNES_MULTIPLAYER5,
	SNES_MULTIPLAYER5_2,
	SNES_JOYPAD,
	SNES_MOUSE_SWAPPED,
	SNES_MOUSE,
	SNES_SUPERSCOPE,
	SNES_JUSTIFIER,
	SNES_JUSTIFIER_2,
	SNES_MAX_CONTROLLER_OPTIONS
};

enum
{
	VIDEOMODE_BLOCKY,
	VIDEOMODE_TV,
	VIDEOMODE_SMOOTH,
	VIDEOMODE_BLEND,
	VIDEOMODE_SUPEREAGLE,
	VIDEOMODE_2XSAI,
	VIDEOMODE_SUPER2XSAI,
	VIDEOMODE_EPX,
	VIDEOMODE_HQ2X,
	VIDEOMODE_HQ3X,
	VIDEOMODE_HQ4X,
	VIDEOMODE_NTSC_C,
	VIDEOMODE_NTSC_S,
	VIDEOMODE_NTSC_R,
	VIDEOMODE_NTSC_M,
	VIDEOMODE_NTSC_TV_C,
	VIDEOMODE_NTSC_TV_S,
	VIDEOMODE_NTSC_TV_R,
	VIDEOMODE_NTSC_TV_M
};

typedef enum S9xMacDeviceSettings {
	Gamepads       = 1,
	Mouse          = 2,
	Mouse2         = 3,
	SuperScope     = 4,
	MultiTap       = 5,
	DoubleMultiTap = 6,
	Justifier1     = 7,
	Justifier2     = 8,
} S9xDeviceSetting;

typedef struct
{
	long long	nextTime[12];
	uint16		buttonMask;
	uint16		toggleMask;
	uint16		tcMask;
	uint16		invertMask;
	SInt32		frequency;
}	AutoFireState;

#define kMacWindowHeight	(SNES_HEIGHT_EXTENDED)
#define MAC_MAX_CHEATS      150

extern volatile bool8	running, s9xthreadrunning;
extern volatile bool8	eventQueued, windowExtend;
extern uint32			controlPad[MAC_MAX_PLAYERS];
extern uint8			romDetect, interleaveDetect, videoDetect, headerDetect;
extern WindowRef		gWindow;
extern uint32			glScreenW, glScreenH;
extern CGFloat			rawMouseX, rawMouseY;
extern int16			mouseX, mouseY;
extern CGRect			glScreenBounds;
extern CGImageRef		macIconImage[118];
extern int				macPadIconIndex, macLegendIconIndex, macMusicBoxIconIndex, macFunctionIconIndex;
extern int				macFrameSkip;
extern int32			skipFrames;
extern int64			lastFrame;
extern unsigned long	spcFileCount, pngFileCount;
extern bool8			finished, cartOpen, autofire;
extern bool8			autoRes, glstretch, gl32bit, vsync, drawoverscan, lastoverscan;
extern long				drawingMethod;
extern int				videoMode;
extern SInt32			macSoundVolume;
extern uint32			macSoundBuffer_ms, macSoundInterval_ms;
extern bool8			macSoundLagEnable;
extern uint16			aueffect;
extern uint8			saveInROMFolder;
extern NSString			*saveFolderPath;
extern int				macCurvatureWarp, macAspectRatio;
extern int				macFastForwardRate, macFrameAdvanceRate;
extern int				inactiveMode;
extern bool8			macQTRecord;
extern uint16			macRecordFlag, macPlayFlag, macQTMovFlag;
extern bool8			startopendlog, showtimeinfrz, enabletoggle, savewindowpos, onscreeninfo;
extern int				musicboxmode;
extern bool8			applycheat;
extern S9xDeviceSetting	deviceSetting, deviceSettingMaster;
extern int				macControllerOption;
extern CGPoint			unlimitedCursor;
extern char				npServerIP[256], npName[256];
extern AutoFireState	autofireRec[MAC_MAX_PLAYERS];

#ifdef MAC_PANTHER_SUPPORT
extern IconRef			macIconRef[118];
#endif

extern bool8			pressedKeys[MAC_MAX_PLAYERS][kNumButtons];
extern bool8            pressedGamepadButtons[MAC_MAX_PLAYERS][kNumButtons];
extern pthread_mutex_t	keyLock;

@protocol S9xEmulationDelegate <NSObject>
- (void)gameLoaded;
- (void)emulationPaused;
- (void)emulationResumed;
@end

@interface S9xView: MTKView
- (void)updatePauseOverlay;

@property (nonatomic, weak) id<S9xEmulationDelegate> emulationDelegate;
@end
extern S9xView			*s9xView;

void AdjustMenus (void);
void UpdateMenuCommandStatus (Boolean);
void ApplyNSRTHeaderControllers (void);
void QuitWithFatalError (NSString *);
void ChangeInputDevice (void);
void PostQueueToSubEventLoop (void);
int PromptFreezeDefrost (Boolean);
uint64 GetMicroseconds(void);

void CopyPressedKeys(uint8 keys[MAC_MAX_PLAYERS][kNumButtons], uint8 gamepadButtons[MAC_MAX_PLAYERS][kNumButtons]);

@interface S9xJoypad : NSObject
@property (nonatomic, assign) uint32 vendorID;
@property (nonatomic, assign) uint32 productID;
@property (nonatomic, assign) uint8 index;
@property (nonatomic, copy) NSString *name;
@end

@interface S9xJoypadInput : NSObject
@property (nonatomic, assign) uint32 cookie;
@property (nonatomic, assign) int32 value;
@property (nonatomic, assign) S9xButtonCode buttonCode;
@end

/// What the window asks of the process running the second game.
typedef NS_OPTIONS(uint32, S9xSecondGameRequest)
{
	S9xSecondGameRequestTogglePause = 1 << 0,
	S9xSecondGameRequestReset = 1 << 1,
	S9xSecondGameRequestSaveState = 1 << 2,
	S9xSecondGameRequestLoadState = 1 << 3
};

/// Frames of a second game, passed from the process running it to the window
/// showing it through shared memory. Its input and requests go the other way:
/// only the window's process reads the gamepads and the keyboard, so a pad can
/// never drive both games.
@interface S9xFrameChannel : NSObject

/// What the other process opens the channel by.
@property (nonatomic, readonly, copy) NSString *name;

/// Makes a new channel, or returns nil when the system refuses.
+ (S9xFrameChannel *)createChannel;

/// Opens a channel another process made, or returns nil when there's no such channel.
+ (S9xFrameChannel *)openChannelWithName:(NSString *)name;

/// Publishes an RGBA frame. Refuses one bigger than the SNES can output.
- (BOOL)writeFrame:(const void *)rgba width:(int)width height:(int)height;

/// The newest frame, or NULL when there's none since the last call.
- (CGImageRef)copyNewestImage CF_RETURNS_RETAINED;

/// Whether the second game's sound is off. It starts off.
@property (nonatomic, assign, getter=isMuted) BOOL muted;

/// Set by the second game.
@property (nonatomic, assign, getter=isPaused) BOOL paused;
@property (nonatomic, assign, getter=isChoosingSlot) BOOL choosingSlot;

- (void)setGamepadButton:(int)button pressed:(BOOL)pressed;
- (void)setKeyButton:(int)button player:(int)player pressed:(BOOL)pressed;
- (void)setRawKey:(int)keyCode pressed:(BOOL)pressed;

/// Lets go of everything held on the gamepad.
- (void)releaseGamepad;

/// Lets go of everything held on the keyboard.
- (void)releaseKeyboard;

/// Sets what's held in the arrays CopyPressedKeys fills, on top of what's there.
- (void)addKeys:(bool8 [MAC_MAX_PLAYERS][kNumButtons])keys gamepadButtons:(bool8 [MAC_MAX_PLAYERS][kNumButtons])gamepadButtons;

/// Fills the raw keyboard array the slot picker reads.
- (void)copyRawKeys:(bool8 *)rawKeys;

- (void)addRequest:(S9xSecondGameRequest)request;

/// Returns the requests made since the last call.
- (S9xSecondGameRequest)takeRequests;

@end

/// Set in a process that runs a second game: frames go here, not to the screen.
extern S9xFrameChannel	*secondGameChannel;

/// Whether this process's game is silent. Moving the sound between two games
/// sets it; other code only mutes for a moment and comes back to it.
extern bool8			gameMuted;

/// Set in the window's process while a second game runs: its input goes here.
extern S9xFrameChannel	*secondGameInput;

/// The first argument that makes the app run a second game for another process.
extern NSString * const S9xSecondGameArgument;

/// Why Open MultiCart can't load a file as its first cart.
typedef NS_ENUM(NSInteger, S9xMultiCartProblem)
{
	S9xMultiCartProblemNone,
	S9xMultiCartProblemNotACart,
	S9xMultiCartProblemNoBIOS
};

typedef NS_ENUM(uint32_t, S9xWatchPointFormat)
{
	S9xWatchPointFormatUnsigned = 1,
	S9xWatchPointFormatSigned = 2,
	S9xWatchPointFormatHex = 3
};

@interface S9xWatchPoint: NSObject

@property (nonatomic, assign) uint32_t address;
@property (nonatomic, assign) uint32_t size;
@property (nonatomic, assign) S9xWatchPointFormat format;

@end

@protocol S9xInputDelegate <NSObject>
- (BOOL)handleInput:(S9xJoypadInput *)input fromJoypad:(S9xJoypad *)joypad;
- (void)deviceSettingChanged:(S9xDeviceSetting)deviceSetting;
- (void)joypadsChanged;
@end

extern id<S9xInputDelegate> inputDelegate;

@interface S9xEngine : NSObject <S9xEmulationDelegate>

@property (nonatomic, weak) id<S9xInputDelegate> inputDelegate;
@property (nonatomic, weak) id<S9xEmulationDelegate> emulationDelegate;

@property (nonatomic, assign) BOOL cheatsEnabled;

- (void)recreateS9xView;

- (void)start;
- (void)stop;
- (void)softwareReset;
- (void)hardwareReset;

// Open the slot picker on the emulation thread, like the Freeze and Defrost keys.
- (void)saveState;
- (void)loadState;

- (BOOL)isRunning;
- (BOOL)isPaused;
- (void)pause;
- (void)quit;
- (void)resume;

- (void)setMuted:(BOOL)muted;

- (BOOL)setButton:(S9xButtonCode)button forKey:(int16)key player:(int8)player oldButton:(S9xButtonCode *)oldButton oldPlayer:(int8 *)oldPlayer oldKey:(int16 *)oldKey;
- (void)clearButton:(S9xButtonCode)button forPlayer:(int8)player;

- (NSArray<S9xJoypad *> *)listJoypads;
- (void)setPlayer:(int8)player forVendorID:(uint32)vendorID productID:(uint32)productID index:(uint32)index oldPlayer:(int8 *)oldPlayer;
- (BOOL)setButton:(S9xButtonCode)button forVendorID:(uint32)vendorID productID:(uint32)productID index:(uint32)index cookie:(uint32)cookie value:(int32)value oldButton:(S9xButtonCode *)oldButton;
- (void)clearJoypadForVendorID:(uint32)vendorID productID:(uint32)productID index:(uint32)index;
- (void)clearJoypadForVendorID:(uint32)vendorID productID:(uint32)productID index:(uint32)index buttonCode:(S9xButtonCode)buttonCode;
- (NSArray<S9xJoypadInput *> *)getInputsForVendorID:(uint32)vendorID productID:(uint32)productID index:(uint32)index;

- (NSString *)labelForVendorID:(uint32)vendorID productID:(uint32)productID cookie:(uint32)cookie value:(int32)value;

/// Whether a file holds a Super Nintendo ROM, without touching the running game.
+ (BOOL)looksLikeROM:(NSURL *)fileURL;

/// What stops a file loading as Open MultiCart's first cart, without touching the running game.
+ (S9xMultiCartProblem)problemWithMultiCart:(NSURL *)cartURL;
+ (S9xMultiCartProblem)problemWithMultiCart:(NSURL *)cartURL biosFolder:(NSURL *)biosFolderURL;

/// Where a second game keeps the save file the first game keeps at `path`, so
/// the same ROM can run as both games.
+ (NSString *)secondGameSavePath:(NSString *)path;

/// Runs a ROM in this process for a window in another one, muted, with input
/// from the channel, until that process stops it. Returns only if the game
/// can't start.
+ (int)runSecondGame:(NSURL *)fileURL channelName:(NSString *)channelName;

/// Sends the second game's input to `channel`; nil ends that and gives the
/// keyboard back to this game.
+ (void)sendInputToSecondGame:(S9xFrameChannel *)channel;

/// Gives the second game a gamepad; zeros leave it none.
+ (void)setSecondGameGamepadVendorID:(uint32)vendorID productID:(uint32)productID index:(uint32)index;

/// Gives the second game the keyboard, or gives it back to this game.
+ (void)setSecondGameUsesKeyboard:(BOOL)usesKeyboard;

- (BOOL)loadROM:(NSURL *)fileURL;
- (BOOL)loadMultiple:(NSArray<NSURL *> *)fileURLs;

- (void)setVideoMode:(int)videoMode;
- (void)setMacFrameSkip:(int)_macFrameSkip;
- (void)setMacFastForwardRate:(int)rate;
- (void)setShowFPS:(BOOL)showFPS;

- (void)setDeviceSetting:(S9xDeviceSetting)_deviceSetting;

- (void)setSuperFXClockSpeedPercent:(uint32_t)clockSpeed;
- (void)setSoundInterpolationType:(int)type;
- (void)setCPUOverclockMode:(int)mode;

- (void)setApplySpecificGameHacks:(BOOL)flag;
- (void)setAllowInvalidVRAMAccess:(BOOL)flag;
- (void)setSeparateEchoBufferFromRAM:(BOOL)flag;
- (void)setDisableSpriteLimit:(BOOL)flag;

- (void)copyRAM:(uint8_t *)buffer length:(size_t)length;

- (NSArray<S9xWatchPoint *> *)getWatchPoints;
- (void)setWatchPoints:(NSArray<S9xWatchPoint *> *)watchPoints;

@end

#endif
