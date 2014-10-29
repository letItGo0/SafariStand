//
//  STCTabListViewCtl.m
//  SafariStand
//
//  Created by hetima on 2014/10/26.
//
//

#import "SafariStand.h"
#import "STCTabListViewCtl.h"
#import "STTabProxyController.h"
#import "STTabProxy.h"
#import "STSafariConnect.h"
#import "STCTabListGroupItem.h"
#import "STQuickSearchModule.h"

//static char tabListViewContext;

/*
 _tabPool にウインドウごとにソートして格納。 // updateTabsTargetTabView:excludesWindow:
 その後 tabs に集約。group も追加。//arrangeTabs
 
 ソートし直す必要がでたときには _tabPool 中の該当する array をソートし直して //tabViewItemUpdated:
 tabs を作り直す //arrangeTabs
 */


@interface STCTabListViewCtl ()

@end

@implementation STCTabListViewCtl {
    BOOL _parasiteMode;
    BOOL _viewAppear;
    NSMutableArray* _tabPool; //array of array
}


+ (STCTabListViewCtl*)viewCtl
{
    return [self viewCtlWithTabView:nil];
}


+ (STCTabListViewCtl*)viewCtlWithTabView:(NSTabView*)tabView
{
    STCTabListViewCtl* result;
    result=[[STCTabListViewCtl alloc]initWithNibName:@"STCTabListViewCtl" bundle:
            [NSBundle bundleWithIdentifier:kSafariStandBundleID]];
    [result setupWithTabView:tabView];
    //[result.aryCtl bind:@"contentArray" toObject:self withKeyPath:@"tabs" options:@{}];
    //[result.aryCtl setFilterPredicate:[NSPredicate predicateWithFormat:@"hidden=0"]];
    
    return result;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter]removeObserver:self];
}


- (void)setupWithTabView:(NSTabView*)tabView
{
    _tabPool=[[NSMutableArray alloc]initWithCapacity:16];
    
    if(tabView){
        _parasiteMode=YES;
        _dragDropEnabled=YES;
        [self loadView];
        
        NSView* vew=[self.tableView enclosingScrollView];
        [vew removeFromSuperview];
        self.view=vew;
        [self.tableView registerForDraggedTypes:@[STTABLIST_DRAG_ITEM_TYPE, @"public.url", @"public.file-url", NSStringPboardType]];
        
        [self updateTabsTargetTabView:tabView excludesWindow:nil];
    }else{
        _parasiteMode=NO;
        _dragDropEnabled=NO;
        //_sortStyle=sortDomain;//test
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:nil];
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(tabViewUpdated:) name:STTabViewDidReplaceNote object:nil];
        
    }
    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(tabViewUpdated:) name:STTabViewDidChangeNote object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(tabViewItemSelected:) name:STTabViewDidSelectItemNote object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(tabViewItemUpdated:) name:STTabProxyDidFinishProgressNote object:nil];
    
    
}


- (void)viewDidLoad
{
    LOG(@"STCTabListViewCtl viewDidLoad");
    [super viewDidLoad];
}


- (void)viewWillAppear
{
    LOG(@"viewWillAppear");
    [super viewWillAppear];
    
    _viewAppear=YES;
    
    if (!_parasiteMode){
        [self updateTabsTargetTabView:nil excludesWindow:nil];
    }
}


- (void)viewDidDisappear
{
    LOG(@"viewDidDisappear");
    [super viewDidDisappear];
    
    _viewAppear=NO;
    
    if (!_parasiteMode){
        self.tabs=nil;
        [_tabPool removeAllObjects];
    }
    //_parasiteMode の場合この後 dealloc される
}

/*
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if(context == &tabListViewContext){
        [self tabViewUpdated:nil];
    }else{
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
    }
}*/


- (void)windowWillClose:(NSNotification*)note
{
    id winCtl=[[note object]windowController];
    if([[winCtl className]isEqualToString:kSafariBrowserWindowController]){
        [self updateTabsTargetTabView:nil excludesWindow:[note object]];
    }
}


- (void)tabViewItemSelected:(NSNotification*)note
{
    if (_parasiteMode) {
        NSTabView* tabView=[note object];
        if (self.view.window==[tabView window]) {
            //もうちょっとうまい方法はあるだろうけど
            [self.tableView reloadData];
        }
    }else{
        [self.tableView reloadData];
    }
}


- (void)tabViewUpdated:(NSNotification*)note
{
    NSTabView* tabView=[note object];
    if (_parasiteMode) {
        //window 基準でチェックしてるので tabView ごと入れ替わっても大丈夫
        if (self.view.window==[tabView window]) {
            [self updateTabsTargetTabView:tabView excludesWindow:nil];
        }
        
    }else{
        //新規ウインドウはこの時点ではisVisible==NO
        [self updateTabsTargetTabView:nil excludesWindow:nil];

    }
}


//ソートし直す必要がでたときには _tabPool 中の該当する array をソートし直す
- (void)tabViewItemUpdated:(NSNotification*)note
{
    if (_sortStyle==sortTab||_sortStyle==sortCreationDate) {
        return;
    }
    STTabProxy* proxy=[note object];
    if (![_tabs containsObject:proxy]) {
        return;
    }
    
    __block NSUInteger poolIndex=NSNotFound;
    [_tabPool enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj containsObject:proxy]) {
            poolIndex=idx;
            *stop=YES;
        }
    }];
    
    if (poolIndex!=NSNotFound) {
        NSArray* tabToSort=[_tabPool objectAtIndex:poolIndex];
        tabToSort=[self sortTabs:tabToSort];
        [_tabPool replaceObjectAtIndex:poolIndex withObject:tabToSort];
    }
    
    [self arrangeTabs];
}


// _tabPool にウインドウごとにソートして格納
- (void)updateTabsTargetTabView:(NSTabView*)tabView excludesWindow:(NSWindow*)excludesWindow
{
    //__block NSMutableArray* ary=[[NSMutableArray alloc]init];
    //NSMutableArray* allTabProxy=[[STTabProxyController si]allTabProxy];
    
    if (!_parasiteMode && !_viewAppear) {
        return;
    }
    
    [_tabPool removeAllObjects];

    if (tabView) {
        NSArray* tabs=[STTabProxyController tabProxiesForTabView:tabView];
        [_tabPool addObject:[self sortTabs:tabs]];
    }else{
    
        STSafariEnumerateBrowserWindow(^(NSWindow *window, NSWindowController *winCtl, BOOL *stop) {
            //ウインドウをまたいでのタブ移動中に出るウインドウを除外する
            NSInteger windowType=0;
            if ([winCtl respondsToSelector:@selector(windowType)]) {
                windowType=(NSInteger)objc_msgSend(winCtl, @selector(windowType));
            }
            if (excludesWindow==window || !(windowType==0||windowType==1)) {
                return;
            }
            
            NSArray* tabs=[STTabProxyController tabProxiesForWindow:window];
            if ([tabs count]>0) {
                [_tabPool addObject:[self sortTabs:tabs]];
            }
            
        });
    }

    [self arrangeTabs];

}


// _tabPool を tabs に集約。group も追加
- (void)arrangeTabs
{
    NSMutableArray* ary=[[NSMutableArray alloc]init];
    for (NSArray* tabs in _tabPool) {
        if (!_parasiteMode) {
            STCTabListGroupItem* test=[[STCWindowGroupItem alloc]init];
            [ary addObject:test];
        }
        
        [ary addObjectsFromArray:tabs];
    }
    
    STCBottomGroupItem* bottomGroup=[[STCBottomGroupItem alloc]init];
    [ary addObject:bottomGroup];
    
    self.tabs=ary;
}


- (NSArray*)sortTabs:(NSArray*)ary
{
    if (_sortStyle==sortTab||_sortStyle==sortCreationDate) {
        return ary;
    }
    
    NSArray* result=[ary sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        if (_sortStyle==sortDomain) {
            return [[obj1 domain]compare:[obj2 domain]];
        }
        return NSOrderedSame;
    }];
    //NSSortDescriptor* result=[NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES selector:@selector(compare:)];
    return result;
}

#pragma mark - table view


- (IBAction)actTableViewClicked:(id)sender
{
    NSInteger clickedIndex=[self.tableView clickedRow];
    if (clickedIndex>=0) {
        STTabProxy* tabProxy=[self.tabs objectAtIndex:clickedIndex];
        if ([tabProxy isKindOfClass:[STTabProxy class]]) {
            [tabProxy selectTab];
            if(!_parasiteMode)[[tabProxy window]makeKeyAndOrderFront:nil];
            return;
        }
        
    }
    
    if ([[NSApp currentEvent]clickCount]==2) {
        [NSApp sendAction:@selector(newTab:) to:nil from:nil];
    }
}


- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    // KI ME U TI
    id obj=[self.tabs objectAtIndex:row];
    if ([obj isKindOfClass:[STTabProxy class]]) {
        return 23.0;
    }else if ([obj isKindOfClass:[STCTabListGroupItem class]]){
        return [obj viewHeight];
    }
    return 20.0;
}


- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    id obj=[self.tabs objectAtIndex:row];
    NSString* idn=@"default";
    
    if ([obj isKindOfClass:[STTabProxy class]]) {
        idn=@"default";
    }else if ([obj isKindOfClass:[STCTabListGroupItem class]]){
        idn=[obj viewIdentifier];
    }
    return [tableView makeViewWithIdentifier:idn owner:nil];
}


- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
    id obj=[self.tabs objectAtIndex:row];
    if ([obj isKindOfClass:[STCTabListGroupItem class]]){
        return [obj isGroupRow];
    }
    return NO;
}

#pragma mark - menu

- (NSMenu*)menuForEmptyTarget
{
    NSMenu* menu=[[NSMenu alloc]initWithTitle:@""];
    NSMenuItem* itm;
    NSMenuItem* separator=nil;
    
    //tab will created in frontmost window
    itm=[menu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@""];
    
    if (_parasiteMode) {
        itm=[menu addItemWithTitle:@"Move Sidebar To Far Side" action:@selector(STToggleSidebarLR:) keyEquivalent:@""];
    }
    
    separator=[NSMenuItem separatorItem];
    
    //goToClipboard
    NSURL* url=HTBestURLFromPasteboard([NSPasteboard generalPasteboard], YES);
    //BOOL goToClipboardMenuItemShown=NO;
    if (url) {
        NSString* title=LOCALIZE(@"Go To \"%@\"");
        NSString* urlStr=[url absoluteString];
        if ([urlStr length]>42) {
            urlStr=[[urlStr substringToIndex:39]stringByAppendingString:@"..."];
        }
        
        title=[NSString stringWithFormat:title, urlStr];
        if (separator) {
            [menu addItem:separator];
            separator=nil;
        }
        itm=[menu addItemWithTitle:title action:@selector(actGoToClipboard:) keyEquivalent:@""];
        [itm setTarget:self];
        [itm setRepresentedObject:url];
        
        //search Clipboard
    }else{
        NSPasteboard* pb=[NSPasteboard generalPasteboard];
        NSString* searchString=[[pb stringForType:NSStringPboardType]stand_moderatedStringWithin:255];
        NSMenu* qsMenu=nil;
        if([searchString length]){
            qsMenu=[[STQuickSearchModule si]standardQuickSearchMenuWithSearchString:searchString];
        }
        if (qsMenu) {
            NSString* title=LOCALIZE(@"Search \"%@\"");
            if ([searchString length]>42) {
                searchString=[[searchString substringToIndex:39]stringByAppendingString:@"..."];
            }
            title=[NSString stringWithFormat:title, searchString];
            if (separator) {
                [menu addItem:separator];
                separator=nil;
            }
            itm=[menu addItemWithTitle:title action:nil keyEquivalent:@""];
            [itm setSubmenu:qsMenu];
        }
    }
    
    return menu;
}


- (NSMenu*)menuForTabProxy:(STTabProxy*)tabProxy
{
    if (![tabProxy isKindOfClass:[STTabProxy class]]){
        return [self menuForEmptyTarget];
    }
    
    NSMenu* menu=[[NSMenu alloc]initWithTitle:@""];
    NSMenuItem* itm;
    NSMenuItem* separator=nil;
    
    itm=[menu addItemWithTitle:@"Close Tab" action:@selector(actClose:) keyEquivalent:@""];
    [itm setTarget:tabProxy];
    
    if ([tabProxy isThereOtherTab]) {
        itm=[menu addItemWithTitle:@"Close Other Tab" action:@selector(actCloseOther:) keyEquivalent:@""];
        [itm setTarget:tabProxy];
        
        itm=[menu addItemWithTitle:@"Move Tab To New Window" action:@selector(actMoveTabToNewWindow:) keyEquivalent:@""];
        [itm setTarget:tabProxy];
    }
    
    separator=[NSMenuItem separatorItem];
    
    if (STSafariCanReloadTab([tabProxy tabViewItem])) {
        if (separator) {
            [menu addItem:separator];
            separator=nil;
        }
        itm=[menu addItemWithTitle:@"Reload Tab" action:@selector(actReload:) keyEquivalent:@""];
        [itm setTarget:tabProxy];
        
        separator=[NSMenuItem separatorItem];
    }
    
    if (_parasiteMode) {
        if (separator) {
            [menu addItem:separator];
            separator=nil;
        }
        itm=[menu addItemWithTitle:@"Move Sidebar To Far Side" action:@selector(STToggleSidebarLR:) keyEquivalent:@""];
    }
    return menu;
}


- (NSMenu*)menuForTabListTableView:(NSTableView*)listView row:(NSInteger)row
{
    if (row==-1) {
        return [self menuForEmptyTarget];
    } else if ([self.tabs count]>row) {
        STTabProxy* tabProxy=[self.tabs objectAtIndex:row];
        return [self menuForTabProxy:tabProxy];
    }
    return nil;
}



#pragma mark - drag and drop

- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
    if (!_dragDropEnabled) {
        return NO;
    }
    
    [pboard declareTypes:@[STTABLIST_DRAG_ITEM_TYPE] owner:self];
    
    NSMutableArray* ary=[[NSMutableArray alloc]initWithCapacity:[rowIndexes count]];
    NSUInteger currentIndex = [rowIndexes firstIndex];
    while (currentIndex != NSNotFound) {
        [ary addObject:@(currentIndex)];
        currentIndex = [rowIndexes indexGreaterThanIndex:currentIndex];
    }
    [pboard setPropertyList:ary forType:STTABLIST_DRAG_ITEM_TYPE];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id < NSDraggingInfo >)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
    if (!_dragDropEnabled) {
        return NSDragOperationNone;
    }
    
    if (operation==NSTableViewDropOn) {
        return NSDragOperationNone;
    }
    
    NSArray *dragTypes = [[info draggingPasteboard]types];
    if([dragTypes containsObject:STTABLIST_DRAG_ITEM_TYPE]){
        return NSDragOperationMove;
    }
    
    
    NSURL *aURL=HTBestURLFromPasteboard([info draggingPasteboard], NO);
    if (aURL) {
        return NSDragOperationCopy;
    }
    
    return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id < NSDraggingInfo >)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
    if (!_dragDropEnabled) {
        return NO;
    }
    
    if (operation==NSTableViewDropOn) {
        return NO;
    }
    
    BOOL acceptDrop = NO;
    NSPasteboard *pb=[info draggingPasteboard];
    NSArray *dragTypes = [pb types];
    
    // KIMEUTI
    NSInteger tabsCount=[self.tabs count];
    if (row>=tabsCount) { //last item is bottom group
        row=tabsCount-1;
    }
    
    if ([dragTypes containsObject:STTABLIST_DRAG_ITEM_TYPE]) {
        acceptDrop = YES;
        
        id sender=[info draggingSource]; //NSTableView
        NSArray *indexes = [pb propertyListForType:STTABLIST_DRAG_ITEM_TYPE];
        
        //drag from same view
        if (sender==aTableView) {
            
            NSMutableArray* aboveArray=[NSMutableArray array];
            NSMutableArray* insertedArray=[NSMutableArray array];
            NSMutableArray* belowArray=[NSMutableArray array];
            
            NSInteger i;
            NSInteger cnt=tabsCount-1;//KIMEUTI last item is bottom group
            for (i=0; i<cnt; i++) {
                STTabProxy* tabProxy=[self.tabs objectAtIndex:i];
                if ([indexes containsObject:[NSNumber numberWithInteger:i]]) {
                    [insertedArray addObject:tabProxy];
                }else if (i<row) {
                    [aboveArray addObject:tabProxy];
                }else{
                    [belowArray addObject:tabProxy];
                }
            }
            [aboveArray addObjectsFromArray:insertedArray];
            [aboveArray addObjectsFromArray:belowArray];
            cnt=[aboveArray count];
            for (i=0; i<cnt; i++) {
                STTabProxy* tabProxy=[aboveArray objectAtIndex:i];
                
                STSafariMoveTabViewItemToIndex(tabProxy.tabViewItem, i);
            }
            
            //drag from other view
        }else if([[sender dataSource]isKindOfClass:[STCTabListViewCtl class]]) {
            STCTabListViewCtl* draggedCtl=(STCTabListViewCtl*)[sender dataSource];
            NSEnumerator* e=[indexes reverseObjectEnumerator];
            NSNumber* index;
            while (index=[e nextObject]) {
                STTabProxy* draggedProxy=[draggedCtl.tabs objectAtIndex:[index integerValue]];
                STSafariMoveTabToOtherWindow(draggedProxy.tabViewItem, [aTableView window], row, YES);
            }
        }
        //drag other element
    } else {
        NSURL *urlToGo=HTBestURLFromPasteboard([info draggingPasteboard], YES);
        if (urlToGo) {
            acceptDrop = YES;
            if (_parasiteMode) {
                id newTabItem=STSafariCreateWKViewOrWebViewAtIndexAndShow([aTableView window], row, YES);
                if(newTabItem){
                    STTabProxy* newProxy=[STTabProxy tabProxyForTabViewItem:newTabItem];
                    [newProxy goToURL:urlToGo];
                }
            }else{
                STSafariGoToURLWithPolicy(urlToGo, poNewTab);
            }
        }
    }
    
    return acceptDrop;
    
}

@end


#pragma mark - Support Classes


@implementation STCTabListTableView

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    NSInteger row = [self rowAtPoint:[self convertPoint:[theEvent locationInWindow] fromView:nil]];
    STCTabListViewCtl* viewCtl=(STCTabListViewCtl*)self.delegate;
    return [viewCtl menuForTabListTableView:self row:row];
}

- (void)highlightSelectionInClipRect:(NSRect)clipRect
{
    LOG(@"%@", NSStringFromRect(clipRect));
}
@end



@implementation STCTabListCellView

- (void)viewDidMoveToWindow
{
    self.mouseIsIn=NO;
    
    NSArray *oldAreas=[self trackingAreas];
    /*for (NSTrackingArea* area in oldAreas) {
     [self removeTrackingArea:area];
     }*/
    if ([oldAreas count]>0) {
        return;
    }
    //[self addTrackingRect:[self bounds] owner:self userData:NULL assumeInside:NO];
    NSTrackingArea* tracking_area = [[NSTrackingArea alloc]initWithRect:[self bounds] options:(NSTrackingMouseEnteredAndExited | NSTrackingInVisibleRect | NSTrackingActiveInActiveApp | NSTrackingEnabledDuringMouseDrag) owner:self userInfo:nil];
    [self addTrackingArea:tracking_area];
}


- (void)mouseEntered:(NSEvent *)theEvent
{
   self.mouseIsIn=YES;
}


- (void)mouseExited:(NSEvent *)theEvent
{
    self.mouseIsIn=NO;
}


- (IBAction)actCloseBtn:(id)sender
{
    STTabProxy* tabProxy=[self objectValue];
    [tabProxy actClose:self];
}


-(void)drawRect:(NSRect)dirtyRect
{
    static NSColor* borderColor;
    static NSColor* lineColor;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        borderColor=[NSColor colorWithCalibratedRed:1.0f/255.0f green:100.0f/255.0f blue:175.0f/255.0f alpha:0.2];
        lineColor=[NSColor colorWithWhite:0.82 alpha:1.0];
    });
    
    STTabProxy* tabProxy=[self objectValue];
    if (tabProxy.isSelected) {
        [borderColor setFill];
        [NSBezierPath fillRect:self.bounds];

    }else{
        [lineColor setStroke];
        [NSBezierPath setDefaultLineWidth:0.0f];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(self.bounds), NSMaxY(self.bounds))
                                  toPoint:NSMakePoint(NSMaxX(self.bounds), NSMaxY(self.bounds))];
    }
}


@end

