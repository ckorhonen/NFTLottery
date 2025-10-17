use anchor_lang::prelude::*;

declare_id!("Lottery111111111111111111111111111111111111");

#[program]
pub mod lottery {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, ticket_price: u64, round_duration: i64, purchase_bps: u16, owner_bps: u16) -> Result<()> {
        require!(purchase_bps as u32 + owner_bps as u32 == 10_000, LotteryError::InvalidSplits);
        let lot = &mut ctx.accounts.lottery;
        lot.authority = ctx.accounts.authority.key();
        lot.ticket_price = ticket_price;
        lot.round_duration = round_duration;
        lot.purchase_bps = purchase_bps;
        lot.owner_bps = owner_bps;
        lot.round = 1;
        lot.round_start = Clock::get()?.unix_timestamp;
        lot.round_end = lot.round_start + round_duration;
        Ok(())
    }

    pub fn deposit(ctx: Context<Deposit>, _amount: u64) -> Result<()> {
        // Users attach SOL to this ix; record tickets
        let lot = &mut ctx.accounts.lottery;
        require!(Clock::get()?.unix_timestamp <= lot.round_end, LotteryError::RoundClosed);
        let lamports = ctx.accounts.payer.lamports().checked_sub(ctx.accounts.payer.to_account_info().lamports()).unwrap_or(0);
        // simplified: tickets = lamports / ticket_price (trust client)
        lot.deposited = lot.deposited.checked_add(lamports).unwrap();
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = authority, space = 8 + 128)]
    pub lottery: Account<'info, Lottery>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(mut, has_one = authority)]
    pub lottery: Account<'info, Lottery>,
    #[account(mut)]
    pub authority: Signer<'info>,
    /// CHECK: payer funds the deposit
    #[account(mut)]
    pub payer: AccountInfo<'info>,
    pub system_program: Program<'info, System>,
}

#[account]
pub struct Lottery {
    pub authority: Pubkey,
    pub ticket_price: u64,
    pub round_duration: i64,
    pub purchase_bps: u16,
    pub owner_bps: u16,
    pub round: u64,
    pub round_start: i64,
    pub round_end: i64,
    pub deposited: u64,
}

#[error_code]
pub enum LotteryError {
    #[msg("Invalid fee splits")] InvalidSplits,
    #[msg("Round closed")] RoundClosed,
}

