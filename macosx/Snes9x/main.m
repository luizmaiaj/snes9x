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
#import <snes9x_framework/snes9x_framework.h>
#import "AppDelegate.h"

int main(int argc, const char * argv[]) {
    // The game window starts this binary again for a second game: the core
    // keeps its state in globals, so one process runs one game.
    if (argc == 4 && strcmp(argv[1], S9xSecondGameArgument.UTF8String) == 0) {
        return [S9xEngine runSecondGame:[NSURL fileURLWithPath:@(argv[3])] channelName:@(argv[2]) configure:^(S9xEngine *engine)
        {
            [AppDelegate registerDefaultSettings];
            [AppDelegate applyGameSettingsToEngine:engine];
        }];
    }

    return NSApplicationMain(argc, argv);
}
