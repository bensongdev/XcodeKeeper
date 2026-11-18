import XCTest
@testable import XcodeKeeper

final class PathGuardTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private var root: URL!

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
        root = try temp.makeDirectory("home/Library/Developer/Xcode/DerivedData")
    }

    private func validate(_ url: URL, roots: [URL]? = nil) throws {
        try PathGuard.validate(url, allowedRoots: roots ?? [root], home: temp.url.appending(path: "home"))
    }

    private func assertRejected(
        _ url: URL, _ expected: PathGuard.Rejection, roots: [URL]? = nil, line: UInt = #line
    ) {
        XCTAssertThrowsError(try validate(url, roots: roots), line: line) { error in
            XCTAssertEqual(error as? PathGuard.Rejection, expected, line: line)
        }
    }

    func testItemInsideRootIsAllowed() throws {
        let item = try temp.makeDirectory("home/Library/Developer/Xcode/DerivedData/App-abc")
        XCTAssertNoThrow(try validate(item))
        let nested = try temp.makeFile("home/Library/Developer/Xcode/DerivedData/App-abc/Build/x.o", bytes: 1)
        XCTAssertNoThrow(try validate(nested))
    }

    func testRootItselfIsAllowed() {
        XCTAssertNoThrow(try validate(root), "단일 항목 대상(예: Xcode 캐시)은 루트 자체를 정리한다")
    }

    func testParentReferenceIsRejected() throws {
        try temp.makeFile("home/Library/Important.txt", bytes: 1)
        let sneaky = URL(fileURLWithPath: root.path + "/../../../Important.txt")
        assertRejected(sneaky, .containsParentReference)
    }

    func testSymlinkPointingOutsideRootIsRejected() throws {
        let outside = try temp.makeDirectory("home/Documents/Project")
        let link = root.appending(path: "Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        assertRejected(link, .outsideAllowedRoots)
    }

    func testSymlinkInsideRootPointingInsideIsAllowed() throws {
        let real = try temp.makeDirectory("home/Library/Developer/Xcode/DerivedData/Real")
        let link = root.appending(path: "Alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertNoThrow(try validate(link))
    }

    func testSymlinkedRootStillAllowsItsChildren() throws {
        let realRoot = try temp.makeDirectory("external/DerivedData")
        let item = try temp.makeDirectory("external/DerivedData/App")
        let linkedRoot = temp.url.appending(path: "home/Library/Developer/Xcode/LinkedDerivedData")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: realRoot)
        XCTAssertNoThrow(try validate(linkedRoot.appending(path: "App"), roots: [linkedRoot]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.path))
    }

    func testSiblingWithSamePrefixIsRejected() throws {
        let sibling = try temp.makeDirectory("home/Library/Developer/Xcode/DerivedData2/App")
        assertRejected(sibling, .outsideAllowedRoots)
    }

    func testPathOutsideAnyRootIsRejected() throws {
        let other = try temp.makeDirectory("home/Library/Developer/Xcode/Archives/2026-01-01")
        assertRejected(other, .outsideAllowedRoots)
    }

    func testMissingPathIsRejected() {
        assertRejected(root.appending(path: "Gone"), .missing)
    }

    func testNonFileURLIsRejected() throws {
        assertRejected(try XCTUnwrap(URL(string: "https://example.com/x")), .notFileURL)
    }

    func testNoRootsMeansNothingIsAllowed() throws {
        let item = try temp.makeDirectory("home/Library/Developer/Xcode/DerivedData/App")
        assertRejected(item, .outsideAllowedRoots, roots: [])
    }

    func testUnsafeRootsAreRefused() throws {
        let home = temp.url.appending(path: "home")
        let item = try temp.makeDirectory("home/Library/Developer/Xcode/DerivedData/App")
        for unsafe in [home, home.appending(path: "Library"), home.appending(path: "Library/Developer/Xcode"),
                       URL(fileURLWithPath: "/")] {
            assertRejected(item, .unsafeRoot, roots: [unsafe])
        }
    }

    func testIsInsideDistinguishesPrefixes() {
        XCTAssertTrue(PathGuard.isInside("/a/Derived", anyOf: ["/a/Derived"]))
        XCTAssertTrue(PathGuard.isInside("/a/Derived/x", anyOf: ["/a/Derived"]))
        XCTAssertFalse(PathGuard.isInside("/a/DerivedData2", anyOf: ["/a/Derived"]))
        XCTAssertFalse(PathGuard.isInside("/a", anyOf: ["/a/Derived"]))
    }

    func testBuiltinTrashTargetsHaveSafeRoots() throws {
        let home = try temp.makeDirectory("realish-home")
        try temp.makeDirectory("realish-home/Library/Developer/Xcode/watchOS DeviceSupport")
        let env = makeEnvironment(home: home)
        for target in BuiltinTargets.all {
            let roots = target.allowedRoots(env)
            switch target.method {
            case .trash:
                XCTAssertFalse(roots.isEmpty, "\(target.id): 휴지통 대상은 허용 루트가 있어야 함")
                for rootURL in roots {
                    XCTAssertTrue(rootURL.path.hasPrefix(home.path + "/Library/"), "\(target.id): \(rootURL.path)")
                    // ~/Library/org.swift.swiftpm처럼 홈에서 두 단계 이상이고, ~/Library/Caches 같은 상위 폴더는 아님
                    XCTAssertGreaterThanOrEqual(rootURL.pathComponents.count, home.pathComponents.count + 2, target.id)
                    XCTAssertFalse(["Library", "Caches", "Developer", "Xcode"].contains(rootURL.lastPathComponent),
                                   "\(target.id): 너무 넓은 루트 \(rootURL.path)")
                }
            case .command, .none:
                XCTAssertTrue(roots.isEmpty, "\(target.id): 휴지통으로 옮기지 않는 대상은 루트가 없어야 함")
            }
        }
    }
}
