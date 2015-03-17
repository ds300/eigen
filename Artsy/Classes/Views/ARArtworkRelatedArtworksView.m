#import "ARArtworkRelatedArtworksView.h"
#import "AREmbeddedModelsViewController.h"
#import "ORStackView+ArtsyViews.h"
#import "ARArtworkSetViewController.h"


@interface ARArtworkRelatedArtworksView() <AREmbeddedModelsDelegate>
@property (nonatomic, assign) BOOL hasRequested;
@property (nonatomic, assign) BOOL hasArtworks;
@property (nonatomic, strong) Artwork *artwork;
@property (nonatomic, strong) SaleArtwork *saleArtwork;
@property (nonatomic, strong) AFJSONRequestOperation *relatedArtworksRequest;
@end


@interface ARArtworkRelatedArtworksContentView : ORStackView
@property (nonatomic, strong) AREmbeddedModelsViewController *artworksVC;
@end

@implementation ARArtworkRelatedArtworksContentView

- (instancetype)initWithTag:(ARRelatedArtworksSubviewOrder)tag
                     module:(ARArtworkMasonryModule *)module
                   artworks:(NSArray *)artworks
                    heading:(NSString *)heading;
{
    if ((self = [super init])) {
        self.tag = (NSInteger)tag;
        [self addPageSubtitleWithString:heading.uppercaseString];
        _artworksVC = [[AREmbeddedModelsViewController alloc] init];
        _artworksVC.constrainHeightAutomatically = YES;
        _artworksVC.activeModule = module;
        [_artworksVC appendItems:artworks];
        [self addSubview:_artworksVC.view withTopMargin:@"0" sideMargin:@"0"];
    }
    return self;
}

@end


@implementation ARArtworkRelatedArtworksView

- (void)updateWithArtwork:(Artwork *)artwork
{
    [self updateWithArtwork:artwork withCompletion:nil];
}

- (void)updateWithArtwork:(Artwork *)artwork withCompletion:(void(^)())completion
{
    if (self.hasRequested) { return; }

    self.artwork = artwork;
    self.hasRequested = YES;

    @weakify(self);

    // TODO: refactor these callbacks to return so we can use
    // results from the values array in a `when`
    KSPromise *salePromise = [artwork onSaleArtworkUpdate:^(SaleArtwork *saleArtwork) {
        self.saleArtwork = saleArtwork;
    } failure:nil];

    KSPromise *fairPromise = [artwork onFairUpdate:nil failure:nil];

    __block PartnerShow *show = nil;
    KSPromise *partnerShowPromise = [artwork onPartnerShowUpdate:^(PartnerShow *s) { show = s; } failure:nil];

    [[KSPromise when:@[salePromise, fairPromise, partnerShowPromise]] then:^id(id value) {
        @strongify(self);

        if (show) {
            [self addSectionsForShow:show];
            return show;
        }

        Sale *auction = self.saleArtwork.auction;
        if (auction) {
            [self addSectionsForAuction:auction];
            return auction;
        }

        Fair *fair = self.fair ?: self.artwork.fair;
        if (fair) {
            [self addSectionsForFair:fair];
            return fair;
        }

        [self addSectionWithRelatedArtworks];
        return nil;

    } error:^id(NSError *error) {
        @strongify(self);
        ARErrorLog(@"Error fetching sale/fair for %@. Error: %@", self.artwork.artworkID, error.localizedDescription);
        [self addSectionWithRelatedArtworks];
        return error;
    }];
}

#pragma mark - Add related works sections

- (void)addSectionsForFair:(Fair *)fair;
{
    @weakify(self);
    [self.artwork getFeaturedShowsAtFair:fair success:^(NSArray *shows) {
        @strongify(self);
        for (PartnerShow *show in shows) {
            [self addSectionWithOtherArtworksInShow:show];
        }
    }];
    [self.artwork getRelatedFairArtworks:fair success:^(NSArray *artworks) {
        @strongify(self);
        [self addSectionWithTag:ARRelatedArtworksSameFair artworks:artworks heading:@"Other works in fair"];
    }];
}

- (void)addSectionsForShow:(PartnerShow *)show;
{
    [self addSectionWithOtherArtworksInShow:show];
    [self addSectionWithArtistArtworks];
    [self addSectionWithRelatedArtworks];
}

- (void)addSectionsForAuction:(Sale *)auction;
{
    @weakify(self);
    [auction getArtworks:^(NSArray *artworks) {
        @strongify(self);
        [self addSectionWithTag:ARRelatedArtworksSameAuction artworks:artworks heading:@"Other works in auction"];
    }];
}

- (void)addSectionWithOtherArtworksInShow:(PartnerShow *)show;
{
    @weakify(self);
    [show getArtworksAtPage:1 success:^(NSArray *artworks) {
        @strongify(self);
        [self addSectionWithTag:ARRelatedArtworksSameShow artworks:artworks heading:@"Other works in show"];
    }];
}

- (void)addSectionWithArtistArtworks;
{
    @weakify(self);
    [self.artwork.artist getArtworksAtPage:1 andParams:nil success:^(NSArray *artworks) {
        @strongify(self);
        [self addSectionWithTag:ARRelatedArtworksArtistArtworks
                       artworks:artworks
                        heading:[NSString stringWithFormat:@"Other works by %@", self.artwork.artist.name]];
    }];
}

- (void)addSectionWithRelatedArtworks;
{
    @weakify(self);
    [self.artwork getRelatedArtworks:^(NSArray *artworks) {
        @strongify(self);
        [self addSectionWithTag:ARRelatedArtworks artworks:artworks heading:@"Related artworks"];
    }];
}

- (void)addSectionWithTag:(ARRelatedArtworksSubviewOrder)tag artworks:(NSArray *)artworks heading:(NSString *)heading;
{
    artworks = [artworks reject:^BOOL(Artwork *artwork) {
        return [artwork.artworkID isEqualToString:self.artwork.artworkID];
    }];

    if (artworks.count == 0) {
        return;
    }

    ARArtworkMasonryLayout layout = [UIDevice isPad] ? [self masonryLayoutForPadWithOrientation:[[UIApplication sharedApplication] statusBarOrientation]] : ARArtworkMasonryLayout2Column;
    ARArtworkMasonryModule *module = [ARArtworkMasonryModule masonryModuleWithLayout:layout andStyle:AREmbeddedArtworkPresentationStyleArtworkMetadata];
    module.layoutProvider = self;

    ARArtworkRelatedArtworksContentView *section = [[ARArtworkRelatedArtworksContentView alloc] initWithTag:tag
                                                                                                     module:module
                                                                                                   artworks:artworks
                                                                                                    heading:heading];

    section.artworksVC.shouldAnimate = self.parentViewController.shouldAnimate;
    section.artworksVC.delegate = self;

    // `-[ORStackView addViewController:toParent:withTopMargin:]` is a bit of a problem with unit-testing, because it
    // will get the view (to add the subview to) from the controller, which is `nil`. You could also setup
    // a view controller just for the tests, but I'm just duplicating the code here for now, but adding the reference
    // to the `section` directly instead.
    //
    [section.artworksVC willMoveToParentViewController:self.parentViewController];
    [self.parentViewController addChildViewController:section.artworksVC];
    [self addSubview:section withTopMargin:@"0" sideMargin:@"0"];
    [section.artworksVC didMoveToParentViewController:self.parentViewController];

    [self layoutIfNeeded];

    [self.parentViewController relatedArtworksView:self didAddSection:section];
}

// TODO Why is this?
//- (CGSize)intrinsicContentSize
//{
//    return CGSizeMake(UIViewNoIntrinsicMetric, self.hasArtworks ? UIViewNoIntrinsicMetric : 0);
//}
#pragma mark - ARArtworkMasonryLayoutProvider

- (ARArtworkMasonryLayout)masonryLayoutForPadWithOrientation:(UIInterfaceOrientation)orientation
{
    return UIInterfaceOrientationIsLandscape(orientation) ? ARArtworkMasonryLayout4Column : ARArtworkMasonryLayout3Column;
}

#pragma mark - AREmbeddedModelsDelegate

- (void)embeddedModelsViewController:(AREmbeddedModelsViewController *)controller shouldPresentViewController:(UIViewController *)viewController
{
    [self.parentViewController relatedArtworksView:self shouldShowViewController:viewController];
}

- (void)embeddedModelsViewController:(AREmbeddedModelsViewController *)controller didTapItemAtIndex:(NSUInteger)index
{
    ARArtworkSetViewController *viewController = [ARSwitchBoard.sharedInstance loadArtworkSet:controller.items inFair:self.fair atIndex:index];
    [self.parentViewController relatedArtworksView:self shouldShowViewController:viewController];
}

- (Fair *)fair
{
    if ([self.parentViewController respondsToSelector:@selector(fair)]) {
        return [self.parentViewController fair];
    } else {
        return nil;
    }
}

@end
