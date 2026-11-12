// Write menu resources with the same PAK version as the installed weapon container.
use std::{env, fs, io::{BufReader, BufWriter, Write}};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 { return Err("usage: pack_menu_text <Game.locres> <output.pak>".into()); }
    let source = fs::read(&args[1])?;
    let mut pak = repak::PakBuilder::new().writer(
        BufWriter::new(fs::File::create(&args[2])?), repak::Version::V11,
        "../../../ProjectPBZ/Content/".into(), Some(0));
    let path = "Localization/Game/en-US/Game.locres";
    pak.write_file(path, false, &source)?;
    pak.write_index()?.flush()?;
    let mut reader = BufReader::new(fs::File::open(&args[2])?);
    let pak = repak::PakBuilder::new().reader(&mut reader)?;
    assert_eq!(pak.get(path, &mut reader)?, source, "resource round trip");
    println!("PAK v11 built and read back: {}", args[2]);
    Ok(())
}
